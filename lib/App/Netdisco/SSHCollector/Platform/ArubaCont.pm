package App::Netdisco::SSHCollector::Platform::ArubaCont;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ArubaCont

=head1 DESCRIPTION

This module collects ARP entries from Aruba controllers.

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from the Aruba controller. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.
Returns a list of hashrefs in the format C<{ mac => MACADDR, ip => IPADDR }>.

=back

=cut

# 从Aruba控制器收集ARP条目
# 该方法用于连接Aruba无线控制器并获取其ARP表信息
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel arpnip() - 开始收集Aruba控制器的ARP条目";

    # 打开伪终端连接
    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "无法运行远程命令 [$hostlabel] " . $ssh->error;
        return ();
    }

    my $expect = Expect->init($pty);
    my $prompt = qr/#/;  # 匹配Aruba控制器提示符

    # 登录控制器并禁用分页
    $expect->expect(10, -re, $prompt);
    $expect->send("no paging\n");
    $expect->expect(10, -re, $prompt);

    # 发送'show arp'命令
    $expect->send("show arp\n");
    my ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # 解析ARP输出
    my @data = split "\n", $before;
    my @arpentries;

    # 匹配控制器ARP输出的正则表达式示例
    foreach my $line (@data) {
        if ($line =~ /(\d+\.\d+\.\d+\.\d+)\s+([\da-f:]+)\s+(vlan\d+)/) {
            push @arpentries, { ip => $1, mac => $2, port => $3 };
            debug "$hostlabel - 解析ARP条目: IP=$1, MAC=$2, 端口=$3";
        }
    }

    debug "$hostlabel - 解析了 " . scalar(@arpentries) . " 个ARP条目";
    return @arpentries;
}

1;
