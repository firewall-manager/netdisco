package App::Netdisco::SSHCollector::Platform::Aruba;

=head1 NAME

App::Netdisco::SSHCollector::Platform::Aruba

=head1 DESCRIPTION

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

# 从Aruba设备收集ARP条目
# 该方法用于连接Aruba设备并获取其ARP表信息
# 使用简单的SSH命令捕获，不需要交互式会话
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";
    # 直接捕获'show arp'命令的输出
    my @data = $ssh->capture("show arp");

    chomp @data;  # 移除每行末尾的换行符
    my @arpentries;

    # Aruba设备ARP输出格式示例:
    # 172.16.20.15  00:24:b2:69:86:7d  vlan    interface   state
    foreach my $line (@data) {
        my @fields = split m/\s+/, $line;  # 按空白字符分割字段

        # 提取IP地址和MAC地址
        push @arpentries, { mac => $fields[1], ip => $fields[0] };
    }
    return @arpentries;
}

1;
