package App::Netdisco::SSHCollector::Platform::GAIAEmbedded;

=head1 NAME

App::Netdisco::SSHCollector::Platform::GAIAEmbedded

=head1 DESCRIPTION

Collect ARP entries from Checkpoint GAIA embedded Systems
To get this Plugin to work you have to add a user like 'netdisco' with
'Network admin' rights in the GAIA embedded OS.

This collector uses "C<arp>" as the command for the arp utility on your
system. If you wish to specify an absolute path, then add an C<arp_command>
item to your configuration:

 device_auth:
   - tag: sshgaia
     driver: cli
     platform: GAIAEmbedded
     only: '192.0.2.1'
     username: oliver
     password: letmein
     arp_command: 'arp'

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

# 从Checkpoint GAIA嵌入式系统收集ARP条目
# 该方法用于连接Checkpoint GAIA嵌入式设备并获取其ARP表信息
# 需要具有"网络管理员"权限的用户
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
    my $prompt = qr/>/;  # 匹配GAIA提示符

    # 等待GAIA提示符（较长的超时时间）
    ($pos, $error, $match, $before, $after) = $expect->expect(30, -re, $prompt);

    # 使用自定义arp命令或默认命令
    my $command = ($args->{arp_command} || 'arp');
    $expect->send("$command -n \n");
    ($pos, $error, $match, $before, $after) = $expect->expect(30, -re, $prompt);

    my @arpentries = ();
    my @lines = split(m/\n/, $before);

    # GAIA ARP输出格式: ? (192.168.17.178) at 5C:F9:DD:71:1F:08 [ether] on LAN1
    # 参考: https://github.com/netdisco/netdisco/issues/365
    my $linereg = qr/([0-9.]+)\s+ether\s+([a-fA-F0-9:]+).+/;
    
    # 解析ARP条目
    foreach my $line (@lines) {
        if ($line =~ $linereg) {
            my ($ip, $mac) = ($1, $2);
            push @arpentries, { mac => $mac, ip => $ip };
        }
    }

    # 退出连接
    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
