package App::Netdisco::SSHCollector::Platform::BigIP;

=head1 NAME

App::Netdisco::SSHCollector::Platform::BigIP

=head1 DESCRIPTION

Collect ARP entries from F5 BigIP load balancers. These are Linux boxes,
but feature an additional, proprietary IP stack which does not show
up in the standard SNMP ipNetToMediaTable.

These devices also feature a CLI interface similar to IOS, which can
either be set as the login shell of the user, or be called from an
ordinary shell. This module assumes the former, and if "show net arp"
can't be executed, falls back to the latter.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

# 从F5 BigIP负载均衡器收集ARP条目
# 该方法用于连接F5 BigIP设备并获取其ARP表信息
# BigIP设备有专有的IP栈，不会在标准SNMP ipNetToMediaTable中显示
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";

    # 首先尝试使用CLI命令
    my @data = $ssh->capture("show net arp");
    # 如果CLI命令失败，则使用tmsh命令
    unless (@data){
        @data = $ssh->capture('tmsh -c "show net arp"');
    }

    chomp @data;  # 移除每行末尾的换行符
    my @arpentries;

    # 解析ARP输出，查找已解析的条目
    foreach (@data){
        if (m/\d{1,3}\..*resolved/){
            my (undef, $ip, $mac) = split(/\s+/);

            # IP地址可能包含VLAN标识符，如172.19.254.143%10，需要清理
            $ip =~ s/%\d+//;

            push(@arpentries, {mac => $mac, ip => $ip});
        }
    }

    return @arpentries;
}

1;
