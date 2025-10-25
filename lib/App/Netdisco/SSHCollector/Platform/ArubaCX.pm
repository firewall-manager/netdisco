package App::Netdisco::SSHCollector::Platform::ArubaCX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCX

=head1 DESCRIPTION

Collect ARP entries from ArubaCX devices

 device_auth:
   - tag: ssharubacx
     driver: cli
     platform: ArubaCX
     only: '192.0.2.1'
     username: oliver
     password: letmein

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

# 从ArubaCX设备收集ARP条目
# 该方法用于连接ArubaCX交换机并获取所有VRF的ARP表信息
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

  my $prompt = qr/#/;    # 匹配设备提示符
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

  # 禁用分页显示
  $expect->send("no page\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

  # 获取所有VRF的ARP表
  $expect->send("show arp all-vrfs\n");
  ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
  my @lines = split(m/\n/, $before);

  # 退出连接
  $expect->send("exit\n");
  $expect->soft_close();

  my @arpentries = ();

  # 'show arp'命令的输出示例:
  #
  # IPv4 Address     MAC                Port         Physical Port                                      State
  # -------------------------------------------------------------------------------------------------------------
  # a.b.c.d          aa:bb:cc:dd:ee:ff  vlanNN       1/1/1                                              reachable
  # ...
  #
  # Total Number Of ARP Entries Listed: 573.
  # -------------------------------------------------------------------------------------------------------------

  # 匹配我们感兴趣的行的模式:
  my $ip_patt  = qr/(?:\d+\.\d+\.\d+\.\d+)/x;                  # IP地址模式
  my $mac_patt = qr/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/x;          # MAC地址模式
  my $linereg  = qr/($ip_patt)\s+($mac_patt)\s+\S+\s+\S+/x;    # 完整行匹配模式

  # 解析每行ARP输出
  foreach my $line (@lines) {
    if ($line =~ $linereg) {
      my ($ip, $mac) = ($1, $2);
      push @arpentries, {mac => $mac, ip => $ip};
    }
  }

  return @arpentries;
}

1;
