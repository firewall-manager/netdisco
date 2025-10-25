package App::Netdisco::SSHCollector::Platform::FTD;

=head1 NAME

App::Netdisco::SSHCollector::Platform::FTD

=head1 DESCRIPTION

Collect IPv4 ARP and IPv6 neighbor entries from Cisco Firepower devices.

You will need the following configuration for the user to automatically enter
C<enable> status after login:

 aaa authorization exec LOCAL auto-enable

To use an C<enable> password separate from the login password, add an
C<enable_password> under C<device_auth> tag in your configuration file:

 device_auth:
   - tag: sshftd
     driver: cli
     platform: FTD
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

=back

=cut

# 从Cisco Firepower设备收集IPv4 ARP和IPv6邻居条目
# 该方法用于连接Cisco FTD设备并获取其ARP表信息
# 支持enable密码认证
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
  $prompt = qr/>\s*$/;
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

#    # 禁用分页显示（已注释，FTD可能不需要）
#    $expect->send("terminal pager 2147483647\n");
#    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

#    # 获取名称解析表（已注释，FTD可能不支持）
#    $expect->send("show names\n");
#    ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);
#    my @names = split(m/\n/, $before);

  # 获取ARP表
  $expect->send("show arp\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(60, -re, $prompt);
  my @lines = split(m/\n/, $before);

  my @arpentries = ();

  # FTD ARP输出格式: ifname 192.0.2.1 0011.2233.4455 123
  my $linereg = qr/[A-z0-9\-\.]+\s([A-z0-9\-\.]+)\s
                     ([0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4})/x;

  # 解析IPv4 ARP条目
  foreach my $line (@lines) {
    if ($line =~ $linereg) {
      my ($ip, $mac) = ($1, $2);

      # 如果IP不是标准格式，尝试从名称解析表中查找（已注释）
      if ($ip !~ m/^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) {

#                foreach my $name (@names) {
#                    if ($name =~ qr/name\s([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\s([\w-]*)/x) {
#                        if ($ip eq $2) {
#                            $ip = $1;
#                        }
#                    }
#                }
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

  # 退出连接
  $expect->send("exit\n");
  $expect->soft_close();

  return @arpentries;
}

1;
