package App::Netdisco::Util::SNMP;

# SNMP工具模块
# SNMP::Info实例的辅助函数

use Dancer qw/:syntax :script/;
use App::Netdisco::Util::DeviceAuth 'get_external_credentials';

use Path::Class 'dir';
use File::Spec::Functions qw/splitdir catdir catfile/;
use MIME::Base64 'decode_base64';
use SNMP::Info;
use JSON::PP ();

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/
  get_communities
  snmp_comm_reindex
  get_mibdirs
  get_mibdirs_shortnames
  decode_and_munge
  sortable_oid
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::SNMP

=head1 DESCRIPTION

Helper functions for L<SNMP::Info> instances.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 get_communities( $device, $mode )

Takes the current C<device_auth> setting and pushes onto the front of the list
the last known good SNMP settings used for this mode (C<read> or C<write>).

=cut

# 获取SNMP团体字符串
# 获取当前device_auth设置并将此模式（read或write）使用的最后已知良好SNMP设置推送到列表前面
sub get_communities {
  my ($device, $mode) = @_;
  $mode ||= 'read';

  my $seen_tags = {}; # 用于清理团体表
  my $config = (setting('device_auth') || []);
  my @communities = ();

  # 首先，如果配置了外部命令则使用
  push @communities, get_external_credentials($device, $mode);

  # 按标签的最后已知良好
  my $tag_name = 'snmp_auth_tag_'. $mode;
  my $stored_tag = eval { $device->community->$tag_name };

  if ($device->in_storage and $stored_tag) {
    foreach my $stanza (@$config) {
      if ($stanza->{tag} and $stored_tag eq $stanza->{tag}) {
        push @communities, {%$stanza, only => [$device->ip]};
        ++$seen_tags->{ $stored_tag };
        last;
      }
    }
  }

  # 清理团体表中的过时标签
  eval { $device->community->update({$tag_name => undef}) }
    if $device->in_storage
       and (not $stored_tag or !exists $seen_tags->{ $stored_tag });

  # 确保所有标记的都在传统团体之前
  push @communities, @$config;

  # 尝试最后已知良好的v2读取
  push @communities, {
    read => 1, write => 0, driver => 'snmp',
    only => [$device->ip],
    community => $device->snmp_comm,
  } if defined $device->snmp_comm and $mode eq 'read';

  # 尝试最后已知良好的v2写入
  my $snmp_comm_rw = eval { $device->community->snmp_comm_rw };
  push @communities, {
    write => 1, read => 0, driver => 'snmp',
    only => [$device->ip],
    community => $snmp_comm_rw,
  } if $snmp_comm_rw and $mode eq 'write';

  return @communities;
}

=head2 snmp_comm_reindex( $snmp, $device, $vlan )

Takes an established L<SNMP::Info> instance and makes a fresh connection using
community indexing, with the given C<$vlan> ID. Works for all SNMP versions.

Inherits the C<vtp_version> from the previous L<SNMP::Info> instance.

Passing VLAN "C<0>" (zero) will reset the indexing to the basic v2 community
or v3 empty context.

=cut

# SNMP团体重新索引
# 获取已建立的SNMP::Info实例并使用团体索引建立新连接，使用给定的VLAN ID
sub snmp_comm_reindex {
  my ($snmp, $device, $vlan) = @_;
  my $ver = $snmp->snmp_ver;
  my $vtp = $snmp->vtp_version;

  if ($ver == 3) {
      my $prefix = '';
      my @comms = get_communities($device, 'read');
      # 查找用户配置的上下文前缀
      foreach my $c (@comms) {
          next unless $c->{tag}
            and $c->{tag} eq (eval { $device->community->snmp_auth_tag_read } || '');
          $prefix = $c->{context_prefix} and last;
      }
      $prefix ||= 'vlan-';

      if ($vlan =~ /^[0-9]+$/i && $vlan) {
        debug sprintf ' [%s] reindexing to "%s%s" (ver: %s, class: %s)',
        $device->ip, $prefix, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($prefix . $vlan));
      } elsif ($vlan =~ /^[a-z0-9]+$/i && $vlan) {
        debug sprintf ' [%s] reindexing to "%s" (ver: %s, class: %s)',
          $device->ip, $vlan, $ver, $snmp->class;
        $snmp->update(Context => ($vlan));
      } else {
        debug sprintf ' [%s] reindexing without context (ver: %s, class: %s)',
          $device->ip, $ver, $snmp->class;
        $snmp->update(Context => '');
      }
  }
  else {
      my $comm = $snmp->snmp_comm;

      debug sprintf ' [%s] reindexing to vlan %s (ver: %s, class: %s)',
        $device->ip, $vlan, $ver, $snmp->class;
      $vlan ? $snmp->update(Community => $comm . '@' . $vlan)
            : $snmp->update(Community => $comm);
  }

  $snmp->cache({ _vtp_version => $vtp });
  return $snmp;
}

=head2 get_mibdirs

Return a list of directories in the `netdisco-mibs` folder.

=cut

# 获取MIB目录
# 返回netdisco-mibs文件夹中的目录列表
sub get_mibdirs {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  return map { dir($home, $_)->stringify }
             @{ setting('mibdirs') || get_mibdirs_shortnames() };
}

# 获取MIB目录短名称
# 返回MIB目录的短名称列表
sub get_mibdirs_shortnames {
  my $home = (setting('mibhome') || dir(($ENV{NETDISCO_HOME} || $ENV{HOME}), 'netdisco-mibs'));
  my @list = map {s|$home/||; $_} grep { m|/[a-z0-9-]+$| } grep {-d} glob("$home/*");
  return \@list;
}

=head2 decode_and_munge( $method, $data )

Takes some data from snmpwalk cache that has been Base64 encoded,
decodes it and then munge to handle data format, before finally pretty
render in JSON format.

=cut

# 获取代码信息
sub get_code_info { return ($_[0]) =~ m/^(.+)::(.*?)$/ }
# 获取子程序名称
sub sub_name      { return (get_code_info $_[0])[1] }
# 获取类名称
sub class_name    { return (get_code_info $_[0])[0] }

# 解码和处理数据
# 获取已Base64编码的snmpwalk缓存数据，解码它然后处理数据格式
sub decode_and_munge {
    my ($munger, $encoded) = @_;
    return undef unless defined $encoded and length $encoded;

    my $json = JSON::PP->new->utf8->pretty->allow_nonref->allow_unknown->canonical;
    $json->sort_by( sub { sortable_oid($JSON::PP::a) cmp sortable_oid($JSON::PP::b) } );

    return undef if $encoded !~ m/^\[/; # 传统格式双重保护防止Web崩溃
    my $data = (@{ from_json($encoded) })[0];

    $data = (ref {} eq ref $data)
      ? { map {($_ => (defined $data->{$_} ? decode_base64($data->{$_}) : undef))}
              keys %$data }
      : (defined $data ? decode_base64($data) : undef);

    return $json->encode( $data ) if not $munger;

    my $sub   = sub_name($munger);
    my $class = class_name($munger);
    Module::Load::load $class;

    # munge_e_type似乎有问题，跳过它
    return $json->encode( $data ) if $sub eq 'munge_e_type' and $class eq 'SNMP::Info';

    $data = (ref {} eq ref $data)
      ? { map {($_ => (defined $data->{$_} ? $class->can($sub)->($data->{$_}) : undef))}
              keys %$data }
      : (defined $data ? $class->can($sub)->($data) : undef);

    return $json->encode( $data );
}

=head2 sortable_oid( $oid, $seglen? )

Take an OID and return a version of it which is sortable using C<cmp>
operator. Works by zero-padding the numeric parts all to be length
C<< $seglen >>, which defaults to 6.

=cut

# 可排序的OID
# 获取OID并返回可使用cmp操作符排序的版本
sub sortable_oid {
  my ($oid, $seglen) = @_;
  $seglen ||= 6;
  return $oid if $oid !~ m/^[0-9.]+$/;
  $oid =~ s/^(\.)//; my $leading = $1;
  $oid = join '.', map { sprintf("\%0${seglen}d", $_) } (split m/\./, $oid);
  return (($leading || '') . $oid);
}

true;
