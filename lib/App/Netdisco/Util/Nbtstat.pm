package App::Netdisco::Util::Nbtstat;

# NetBIOS状态工具模块
# 支持Netdisco应用程序各个部分的辅助子程序

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::Node 'check_mac';
use App::Netdisco::AnyEvent::Nbtstat;
use Encode;

use base 'Exporter';
our @EXPORT      = ();
our @EXPORT_OK   = qw/ nbtstat_resolve_async store_nbt /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::Nbtstat

=head1 DESCRIPTION

Helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 nbtstat_resolve_async( $ips )

This method uses an asynchronous AnyEvent NetBIOS node status requester
C<App::Netdisco::AnyEvent::Nbtstat>.

Given a reference to an array of hashes will connects to the C<IPv4> of a
node and gets NetBIOS node status information.

Returns the supplied reference to an array of hashes with MAC address,
NetBIOS name, NetBIOS domain/workgroup, NetBIOS user, and NetBIOS server
service status for addresses which responded.

=cut

# 异步NetBIOS状态解析
# 使用异步AnyEvent NetBIOS节点状态请求器
sub nbtstat_resolve_async {
  my $ips = shift;

  # 获取超时和间隔设置
  my $timeout  = (setting('nbtstat_response_timeout') || setting('nbtstat_timeout') || 1);
  my $interval = setting('nbtstat_interval') || 0.02;

  # 创建NetBIOS状态查询器
  my $stater = App::Netdisco::AnyEvent::Nbtstat->new(timeout => $timeout, interval => $interval);

  # 设置条件变量
  my $cv = AE::cv;
  $cv->begin(sub { shift->send });

  # 为每个IP地址执行NetBIOS查询
  foreach my $hash_ref (@$ips) {
    my $ip = $hash_ref->{'ip'};
    $cv->begin;
    $stater->nbtstat(
      $ip,
      sub {
        my $res = shift;
        _filter_nbname($ip, $hash_ref, $res);
        $cv->end;
      }
    );
  }

  # 递减条件变量计数器以取消发送声明
  $cv->end;

  # 等待解析器执行所有解析
  $cv->recv;

  # 关闭套接字
  undef $stater;

  return $ips;
}

# 过滤NetBIOS名称/信息
# 处理NetBIOS节点状态响应并提取相关信息
sub _filter_nbname {
  my $ip          = shift;
  my $hash_ref    = shift;
  my $node_status = shift;

  my $server = 0;
  my $nbname = '';
  my $domain = '';
  my $nbuser = '';

  # 处理NetBIOS名称记录
  for my $rr (@{$node_status->{'names'}}) {
    my $suffix = defined $rr->{'suffix'} ? $rr->{'suffix'} : -1;
    my $G      = defined $rr->{'G'}      ? $rr->{'G'}      : '';
    my $name   = defined $rr->{'name'}   ? $rr->{'name'}   : '';

    # 提取域/工作组信息
    if ($suffix == 0 and $G eq "GROUP") {
      $domain = $name;
    }

    # 提取用户信息
    if ($suffix == 3 and $G eq "UNIQUE") {
      $nbuser = $name;
    }

    # 提取计算机名称
    if ($suffix == 0 and $G eq "UNIQUE") {
      $nbname = $name unless $name =~ /^IS~/;
    }

    # 检查服务器服务
    if ($suffix == 32 and $G eq "UNIQUE") {
      $server = 1;
    }
  }

  # 检查是否找到计算机名称
  unless ($nbname) {
    debug sprintf ' nbtstat no computer name found for %s', $ip;
    return;
  }

  my $mac = $node_status->{'mac_address'} || '';

  # 验证MAC地址
  unless (check_mac($mac, $ip)) {

    # 假设它是我们在此IP上看到的最后一个MAC
    my $node_ip = schema(vars->{'tenant'})->resultset('NodeIp')->single({ip => $ip, -bool => 'active'});

    if (!defined $node_ip) {
      debug sprintf ' no MAC for %s returned by nbtstat or in DB', $ip;
      return;
    }
    $mac = $node_ip->mac;
  }

  # 设置结果哈希
  $hash_ref->{'ip'}     = $ip;
  $hash_ref->{'mac'}    = $mac;
  $hash_ref->{'nbname'} = Encode::decode('UTF-8', $nbname);
  $hash_ref->{'domain'} = Encode::decode('UTF-8', $domain);
  $hash_ref->{'server'} = $server;
  $hash_ref->{'nbuser'} = Encode::decode('UTF-8', $nbuser);

  return;
}

=head2 store_nbt($nb_hash_ref, $now?)

Stores entries in C<node_nbt> table from the provided hash reference; MAC
C<mac>, IP C<ip>, Unique NetBIOS Node Name C<nbname>, NetBIOS Domain or
Workgroup C<domain>, whether the Server Service is running C<server>,
and the current NetBIOS user C<nbuser>.

Adds new entry or time stamps matching one.

Optionally a literal string can be passed in the second argument for the
C<time_last> timestamp, otherwise the current timestamp (C<LOCALTIMESTAMP>) is used.

=cut

# 存储NetBIOS信息
# 将提供的哈希引用中的条目存储到node_nbt表中
sub store_nbt {
  my ($hash_ref, $now) = @_;
  $now ||= 'LOCALTIMESTAMP';

  # 在事务中存储或更新NetBIOS信息
  schema(vars->{'tenant'})->txn_do(sub {
    my $row = schema(vars->{'tenant'})->resultset('NodeNbt')->update_or_new(
      {
        mac       => $hash_ref->{'mac'},
        ip        => $hash_ref->{'ip'},
        nbname    => $hash_ref->{'nbname'},
        domain    => $hash_ref->{'domain'},
        server    => $hash_ref->{'server'},
        nbuser    => $hash_ref->{'nbuser'},
        active    => \'true',
        time_last => \$now,
      },
      {key => 'primary', for => 'update',}
    );

    # 如果是新记录，设置首次时间戳
    if (!$row->in_storage) {
      $row->set_column(time_first => \$now);
      $row->insert;
    }
  });

  return;
}

1;
