package App::Netdisco::SSHCollector::Platform::IOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOS

=head1 DESCRIPTION

Collect ARP entries from Cisco IOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<{ mac =E<gt> MACADDR, ip =E<gt> IPADDR }>.

=back

=cut

my $if_name_map = {
  Vl => "Vlan",
  Lo => "Loopback",
  Fa => "FastEthernet",
  Gi => "GigabitEthernet",
  Tw => "TwoGigabitEthernet",
  Fi => "FiveGigabitEthernet",
  Te => "TenGigabitEthernet",
  Twe => "TwentyFiveGigE",
  Fo => "FortyGigabitEthernet",
  Hu => "HundredGigE",
  Po => "Port-channel",
  Bl => "Bluetooth",
};

# 从Cisco IOS设备收集ARP条目
# 该方法用于连接Cisco IOS设备并获取其ARP表信息
# 使用简单的SSH命令捕获，不需要交互式会话
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";
    # 直接捕获'show ip arp'命令的输出
    my @data = $ssh->capture("show ip arp");

    chomp @data;  # 移除每行末尾的换行符
    my @arpentries;

    # IOS ARP输出格式: Internet  172.16.20.15   13   0024.b269.867d  ARPA FastEthernet0/0.1
    foreach my $line (@data) {
        next unless $line =~ m/^Internet/;  # 只处理以"Internet"开头的行
        my @fields = split m/\s+/, $line;  # 按空白字符分割字段

        # 提取MAC地址和IP地址
        push @arpentries, { mac => $fields[3], ip => $fields[1] };
    }

    return @arpentries;
}

# 从Cisco IOS设备收集MAC地址表
# 该方法用于获取交换机的MAC地址表信息，包括VLAN、端口和MAC地址的映射关系
sub macsuck {
  my ($self, $hostlabel, $ssh, $args) = @_;

  debug "$hostlabel $$ macsuck()";
  # 构建命令序列：禁用分页并获取MAC地址表
  my $cmds = <<EOF;
terminal length 0
show mac address-table
EOF
  my @data = $ssh->capture({stdin_data => $cmds}); chomp @data;
  if ($ssh->error) {
    info "$hostlabel $$ SSH命令出错 " . $ssh->error;
    return;
  }

  # IOS MAC地址表输出格式:
  #hostname#sh mac address-table
  #          Mac Address Table
  #-------------------------------------------
  #
  #Vlan    Mac Address       Type        Ports
  #----    -----------       --------    -----
  # All    0100.0ccc.cccc    STATIC      CPU
  #  10    xxxx.7fc7.xxxx    DYNAMIC     Gi0/1/0
  #  10    xxxx.027c.xxxx    STATIC      CPU

  # 匹配MAC地址表行的正则表达式
  my $re_mac_line = qr/^\s*(All|[0-9]+)\s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4})\s+\S+\s+([a-zA-Z]+)([0-9\/\.]*)/i;
  my $macentries = {};

  # 解析MAC地址表条目
  foreach my $line (@data) {
    if ($line && $line =~ m/$re_mac_line/) {
      # 扩展接口名称（使用接口名称映射表）
      my $port = sprintf '%s%s', ($if_name_map->{$3} || $3), ($4 || '');
      # 处理VLAN ID（"All"映射为0）
      my $vlan = ($1 ? ($1 eq 'All' ? 0 : $1) : 0);

      # 统计MAC地址条目
      ++$macentries->{$vlan}->{$port}->{mac_as_ieee($2)};
    }
  }

  return $macentries;
}

1;
