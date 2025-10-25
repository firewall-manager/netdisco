package App::Netdisco::SSHCollector::Platform::ASAContext;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ASAContext

=head1 DESCRIPTION

Collect IPv4 ARP and IPv6 neighbor entries from Cisco ASA devices.

You will need the following configuration for the user to automatically enter
C<enable> status after login:

aaa authorization exec LOCAL auto-enable

To use an C<enable> password seaparate from the login password, add an
C<enable_password> under C<device_auth> in your configuration file:

device_auth:
    - tag: sshasa
      driver: cli
      platform: ASAContext
      only: '192.0.2.1'
      username: oliver
      password: letmein
      enable_password: myenablepass

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP and neighbor entries from device. C<$host> is the hostname or IP
address of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

This was kindly created by @haught and mentioned in https://github.com/netdisco/netdisco/issues/754 
as being a context-aware version of ASA.pm.

The code is imported from https://github.com/haught/netdisco/blob/ASAContext/lib/App/Netdisco/SSHCollector/Platform/ASAContext.pm.
However this version did not have some ASA.pm improvements added in dc9feb747f..b58a62f300, 
so we tried to merge all of this in here. However we lack the ability to try it, so we also 
left in place the original ASA.pm which is confirmed to work.

=back

=cut

# 从Cisco ASA设备收集IPv4 ARP和IPv6邻居条目
# 该方法支持多上下文环境，需要遍历所有上下文并收集每个上下文的ARP信息
sub arpnip {
  my ($self, $hostlabel, $ssh, $args) = @_;

  debug "$hostlabel $$ arpnip()";

  # 打开伪终端连接
  my ($pty, $pid) = $ssh->open2pty;
  unless ($pty) {
    debug "无法运行远程命令 [$hostlabel] " . $ssh->error;
    return ();
  }
  my $expect = Expect->init($pty);

  my ($pos, $error, $match, $before, $after);
  my $prompt;

  # 如果提供了enable密码，则先进入特权模式
  if ($args->{enable_password}) {
    $prompt = qr/>/;    # 匹配用户模式提示符
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send("enable\n");

    $prompt = qr/Password:/;    # 匹配密码提示符
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send($args->{enable_password} . "\n");
  }

  # 等待特权模式提示符
  $prompt = qr/#\s*$/;
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

  # 禁用分页显示
  $expect->send("terminal pager 2147483647\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

  # 切换到系统上下文
  $expect->send("changeto system\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

  # 获取所有上下文列表
  $expect->send("show run | include ^context\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);
  my @contexts = split(m/\n/, $before);

  my @arpentries = ();

  # 遍历所有上下文（跳过第一个，因为它是系统上下文）
  for (my $i = 1; $i < scalar @contexts; $i++) {
    $contexts[$i] =~ s/context //;    # 移除"context "前缀
    debug "$hostlabel/$contexts[$i]";

    # 切换到指定上下文
    $expect->send("changeto context $contexts[$i]\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # 获取名称解析表（用于将主机名解析为IP地址）
    $expect->send("show names\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);

    my @names = split(m/\n/, $before);

    # 确保分页已禁用
    $expect->send("terminal pager 2147483647\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    # 获取ARP表
    $expect->send("show arp\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);

    my @lines = split(m/\n/, $before);

    # ASA ARP输出格式: ifname 192.0.2.1 0011.2233.4455 123
    my $linereg = qr/[A-z0-9\-\.]+\s([A-z0-9\-\.]+)\s
            ([0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4})/x;

    # 解析IPv4 ARP条目
    foreach my $line (@lines) {
      if ($line =~ $linereg) {
        my ($ip, $mac) = ($1, $2);

        # 如果IP不是标准格式，尝试从名称解析表中查找
        if ($ip !~ m/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) {
          foreach my $name (@names) {
            if ($name =~ qr/name\s([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s([\w-]*)/x) {
              if ($ip eq $2) {
                $ip = $1;    # 使用解析到的IP地址
              }
            }
          }
        }

        # 只添加有效的IPv4地址
        if ($ip =~ m/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) {
          push @arpentries, {mac => $mac, ip => $ip};
        }
      }
    }

    # 开始收集IPv6邻居条目
    $expect->send("show ipv6 neighbor\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);

    @lines = split(m/\n/, $before);

    # IPv6邻居输出格式: IPv6 age MAC state ifname
    $linereg = qr/([0-9a-fA-F\:]+)\s+[0-9]+\s
            ([0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4})/x;

    # 解析IPv6邻居条目
    foreach my $line (@lines) {
      if ($line =~ $linereg) {
        my ($ip, $mac) = ($1, $2);
        push @arpentries, {mac => $mac, ip => $ip};
      }
    }

    # IPv6收集结束
  }

  # 退出连接
  $expect->send("exit\n");
  $expect->soft_close();
  return @arpentries;
}

1;

