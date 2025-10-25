package App::Netdisco::Util::DNS;

# DNS工具模块
# 提供支持Netdisco应用程序各个部分的辅助子程序

use strict;
use warnings;
use Dancer ':script';

use Net::DNS;
use Scalar::Util qw/blessed reftype/;
use NetAddr::IP::Lite ':lower';

use base 'Exporter';
our @EXPORT      = ();
our @EXPORT_OK   = qw/hostname_from_ip ipv4_from_hostname/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

=head1 NAME

App::Netdisco::Util::DNS

=head1 DESCRIPTION

A set of helper subroutines to support parts of the Netdisco application.

There are no default exports, however the C<:all> tag will export all
subroutines.

=head1 EXPORT_OK

=head2 hostname_from_ip( $ip, \%opts? )

Given an IP address (either IPv4 or IPv6), return the canonical hostname.

C<< %opts >> can override the various timeouts available in
L<Net::DNS::Resolver>:

=over 4

=item C<tcp_timeout>: 120 (seconds)

=item C<udp_timeout>: 30 (seconds)

=item C<retry>: 4 (attempts)

=item C<retrans>: 5 (timeout)

=back

Returns C<undef> if no PTR record exists for the IP.

=cut

# 从IP地址获取主机名
# 根据IP地址（IPv4或IPv6）返回规范的主机名
sub hostname_from_ip {
  my ($ip, $opts) = @_;
  return unless $ip;
  my $skip     = setting('dns')->{'no'};
  my $ETCHOSTS = setting('dns')->{'ETCHOSTS'};

  return if check_acl_no_ipaddr_only($ip, $skip);

  # 检查/etc/hosts文件，如果找到则短路返回
  foreach my $name (reverse sort keys %$ETCHOSTS) {
    if ($ETCHOSTS->{$name}->[0]->[0] eq $ip) {
      return $name;
    }
  }

  # 创建DNS解析器并设置超时参数
  my $res = Net::DNS::Resolver->new;
  $res->tcp_timeout($opts->{tcp_timeout} || 120);
  $res->udp_timeout($opts->{udp_timeout} || 30);
  $res->retry($opts->{retry}             || 4);
  $res->retrans($opts->{retrans}         || 5);
  my $query = $res->search($ip);

  # 查找PTR记录
  if ($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "PTR";
      return $rr->ptrdname;
    }
  }

  return undef;
}

=head2 ipv4_from_hostname( $name )

Given a host name will return the first IPv4 address.

Returns C<undef> if no A record exists for the name.

=cut

# 从主机名获取IPv4地址
# 根据主机名返回第一个IPv4地址
sub ipv4_from_hostname {
  my $name = shift;
  return undef unless $name;
  my $ETCHOSTS = setting('dns')->{'ETCHOSTS'};

  # 检查/etc/hosts文件，如果找到则短路返回
  if (exists $ETCHOSTS->{$name} and $ETCHOSTS->{$name}->[0]->[0]) {
    my $ip = NetAddr::IP::Lite->new($ETCHOSTS->{$name}->[0]->[0]);
    return $ip->addr if $ip and $ip->bits == 32;
  }

  # 创建DNS解析器并查询A记录
  my $res   = Net::DNS::Resolver->new;
  my $query = $res->search($name);

  if ($query) {
    foreach my $rr ($query->answer) {
      next unless $rr->type eq "A";
      return $rr->address;
    }
  }

  return undef;
}

# 为避免与App::Netdisco::Util::Permission的循环依赖
# 仅支持IP地址和CIDR块

# 检查ACL中仅IP地址的配置
sub check_acl_no_ipaddr_only {
  my ($thing, $config) = @_;
  return 0 unless defined $thing and defined $config;

  # 提取真实的IP地址
  my $real_ip = $thing;
  if (blessed $thing) {
    $real_ip
      = ($thing->can('alias')
      ? $thing->alias
      : ($thing->can('ip') ? $thing->ip : ($thing->can('addr') ? $thing->addr : $thing)));
  }
  return 0 if !defined $real_ip or blessed $real_ip;    # 我们不理解的类

  # 处理配置格式
  $config = [$config] if ref '' eq ref $config;
  if (ref [] ne ref $config) {
    error "error: acl is not a single item or list (cannot compare to $real_ip)";
    return 0;
  }
  my $all = (scalar grep { $_ eq 'op:and' } @$config);

  # 常见情况：在ACL中使用纯IP，所以使用字符串比较以提高速度
  my $find = (scalar grep { not reftype $_ and $_ eq $real_ip } @$config);
  return 1 if $find and not $all;

  my $addr = NetAddr::IP::Lite->new($real_ip) or return 0;

  # 遍历配置列表进行匹配
INLIST: foreach (@$config) {
    my $item = $_;    # 必须复制以便安全修改
    next INLIST if !defined $item or $item eq 'op:and';

    # 检查否定操作符
    my $neg = ($item =~ s/^!//);

    # 处理组匹配
    if ($item =~ m/^group:(.+)$/) {
      my $group = $1;
      setting('host_groups')->{$group} ||= [];

      if ($neg xor check_acl_no_ipaddr_only($thing, setting('host_groups')->{$group})) {
        return 1 if not $all;
      }
      else {
        return 0 if $all;
      }
      next INLIST;
    }

    # 处理范围匹配（IPv6和IPv4）
    if ($item =~ m/[:.]([a-f0-9]+)-([a-f0-9]+)$/i) {
      my $first = $1;
      my $last  = $2;

      # IPv6范围处理
      if ($item =~ m/:/) {
        next INLIST if $addr->bits != 128 and not $all;

        $first = hex $first;
        $last  = hex $last;

        (my $header = $item) =~ s/:[^:]+$/:/;
        foreach my $part ($first .. $last) {
          my $ip = NetAddr::IP::Lite->new($header . sprintf('%x', $part) . '/128') or next;
          if ($neg xor ($ip == $addr)) {
            return 1 if not $all;
            next INLIST;
          }
        }
        return 0 if (not $neg and $all);
        return 1 if ($neg     and not $all);
      }

      # IPv4范围处理
      else {
        next INLIST if $addr->bits != 32 and not $all;

        (my $header = $item) =~ s/\.[^.]+$/./;
        foreach my $part ($first .. $last) {
          my $ip = NetAddr::IP::Lite->new($header . $part . '/32') or next;
          if ($neg xor ($ip == $addr)) {
            return 1 if not $all;
            next INLIST;
          }
        }
        return 0 if (not $neg and $all);
        return 1 if ($neg     and not $all);
      }
      next INLIST;
    }

    # 可能是错误的东西，IP/主机是唯一剩下的选项
    next INLIST if ref $item;

    # 处理单个IP或CIDR块
    my $ip = NetAddr::IP::Lite->new($item) or next INLIST;
    next INLIST if $ip->bits != $addr->bits and not $all;

    if ($neg xor ($ip->contains($addr))) {
      return 1 if not $all;
    }
    else {
      return 0 if $all;
    }
    next INLIST;
  }

  return ($all ? 1 : 0);
}

1;
