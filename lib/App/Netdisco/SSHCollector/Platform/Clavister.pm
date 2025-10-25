package App::Netdisco::SSHCollector::Platform::Clavister;

=head1 NAME

App::Netdisco::SSHCollector::Platform::Clavister

=head1 DESCRIPTION

Collect ARP entries from Clavister firewalls.
These devices does not expose mac table through snmp.

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
Returns an array of hashrefs in the format { mac => MACADDR, ip => IPADDR }.

=back

=cut

# 从Clavister防火墙收集ARP条目
# 该方法用于连接Clavister防火墙并获取其邻居缓存信息
# Clavister设备不通过SNMP暴露MAC表，需要使用neighborcache命令
sub arpnip {
  my ($self, $hostlabel, $ssh, @args) = @_;
  debug "$hostlabel $$ arpnip()";

  # 获取邻居缓存信息
  my @data = $ssh->capture("neighborcache");
  chomp @data;    # 移除每行末尾的换行符
  my @arpentries;

  # 解析邻居缓存输出，跳过标题行
  foreach (@data) {
    next if /^Contents of Active/;    # 跳过标题行
    next if /^Idx/;                   # 跳过索引行
    next if /^---/;                   # 跳过分隔符行
    my @fields = split /\s+/, $_;     # 按空白字符分割字段
    my $mac    = $fields[2];          # MAC地址在第3个字段
    my $ip     = $fields[3];          # IP地址在第4个字段
    push(@arpentries, {mac => $mac, ip => $ip});
  }
  return @arpentries;
}

1;
