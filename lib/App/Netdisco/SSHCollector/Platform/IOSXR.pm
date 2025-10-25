package App::Netdisco::SSHCollector::Platform::IOSXR;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXR

=head1 DESCRIPTION

Collect ARP entries from IOSXR routers using Expect

This is a reworked version of the IOSXR module, and it is suitable
for both 32- and 64-bit IOSXR.

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

# 从Cisco IOS-XR路由器收集ARP条目
# 该方法用于连接IOS-XR设备并获取所有VRF的ARP表信息
# 适用于32位和64位IOS-XR系统
sub arpnip {
  my ($self, $hostlabel, $ssh, $args) = @_;

  debug "$hostlabel $$ arpnip()";

  # 打开伪终端连接
  my ($pty, $pid) = $ssh->open2pty;
  unless ($pty) {
    warn "无法运行远程命令 [$hostlabel] " . $ssh->error;
    return ();
  }
  my $expect = Expect->init($pty);

  my ($pos, $error, $match, $before, $after);
  my $prompt  = qr/# +$/;    # 匹配IOS-XR特权模式提示符
  my $timeout = 10;

  # 等待设备提示符
  ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

  # 禁用分页显示
  $expect->send("terminal length 0\n");
  ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

  # 获取所有VRF的ARP表
  $expect->send("show arp vrf all\n");
  ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

  my @arpentries = ();
  my @data       = split(m/\n/, $before);

  # 解析ARP输出，提取IP地址和MAC地址
  foreach (@data) {
    my ($ip, $age, $mac, $state, $t, $iface) = split(/\s+/);

    # 验证IP和MAC地址格式
    if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/([0-9a-f]{4}\.){2}[0-9a-f]{4}/i) {
      push(@arpentries, {ip => $ip, mac => $mac});
    }
  }

  # 退出连接
  $expect->send("exit\n");
  $expect->hard_close();

  return @arpentries;
}

1;
