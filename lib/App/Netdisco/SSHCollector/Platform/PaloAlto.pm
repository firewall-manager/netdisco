package App::Netdisco::SSHCollector::Platform::PaloAlto;

=head1 NAME

App::Netdisco::SSHCollector::Platform::PaloAlto

=head1 DESCRIPTION

Collect ARP entries from PaloAlto devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP and neighbor entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac => MACADDR, ip => IPADDR }>.

=back

=cut

# 从PaloAlto设备收集ARP和邻居条目
# 该方法用于连接PaloAlto防火墙并获取其ARP表和IPv6邻居信息
sub arpnip{
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
    my $prompt = qr/> \r?$/;  # 匹配PaloAlto提示符

    # 等待设备提示符
    ($pos, $error, $match, $before, $after) = $expect->expect(20, -re, $prompt);
    # 启用脚本模式以禁用回显
    $expect->send("set cli scripting-mode on\n");

    # PaloAlto CLI会回显内容，导致我们看到提示符3次额外
    # 幸运的是，前面的命令禁用了这个，所以我们只需要处理一次
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # 获取IPv4 ARP条目
    $expect->send("show arp all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    my @arpentries;
    # 解析IPv4 ARP输出
    for (split(/\r\n/, $before)){
        next unless $_ =~ m/(\d{1,3}\.){3}\d{1,3}/;  # 跳过不包含IP地址的行
        my ($tmp, $ip, $mac) = split(/\s+/);
        if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/([0-9a-f]{2}:){5}[0-9a-f]{2}/i) {
             push(@arpentries, { ip => $ip, mac => $mac });
        }
    }

    # 获取IPv6邻居条目
    $expect->send("show neighbor interface all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    # 解析IPv6邻居输出
    for (split(/\r\n/, $before)){
        next unless $_ =~ m/([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}/;  # 跳过不包含IPv6地址的行
        my ($tmp, $ip, $mac) = split(/\s+/);
        if ($ip =~ m/([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}/ && $mac =~ m/([0-9a-f]{2}:){5}[0-9a-f]{2}/i) {
             push(@arpentries, { ip => $ip, mac => $mac });
        }
    }
    # 退出连接
    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
