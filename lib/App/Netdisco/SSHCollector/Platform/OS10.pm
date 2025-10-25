package App::Netdisco::SSHCollector::Platform::OS10;

=head1 NAME

App::Netdisco::SSHCollector::Platform::OS10

=head1 DESCRIPTION

Collect ARP entries from Dell OS10 devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Regexp::Common 'net';

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

my $if_name_map = {Vl => "Vlan", Lo => "Loopback", Eth => "Ethernet", Po => "Port-channel",};

# 从Dell OS10设备收集ARP条目
# 该方法用于连接Dell OS10交换机并获取所有VRF的ARP表信息
sub arpnip {
  my ($self, $hostlabel, $ssh, $args) = @_;

  debug "$hostlabel $$ arpnip()";

  # 打开伪终端连接
  my ($pty, $pid) = $ssh->open2pty;
  unless ($pty) {
    warn "无法运行远程命令 [$hostlabel] " . $ssh->error;
    return ();
  }

  # 调试选项（已注释）
  # $Expect::Debug = 1;
  # $Expect::Exp_Internal = 1;

  my $expect = Expect->init($pty);
  $expect->raw_pty(1);

  my ($pos, $error, $match, $before, $after);
  my $prompt  = qr/# +$/;    # 匹配OS10特权模式提示符
  my $timeout = 60;

  # 等待设备提示符
  ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

  # 获取所有VRF，跳过标题行
  $expect->send("show ip vrf | except VRF-Name | no-more \n");
  ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
  my @vrfs = split(/\R/, $before);

  # VRF名称的正则表达式
  my $vrf_re = qr/^([a-z\-_0-9\.]+)\s+.+$/i;

  # IP ARP匹配正则表达式
  my $iparp_re = qr/^((\d{1,3}\.){3}\d{1,3})\s*(([0-9a-f]{2}[:-]){5}[0-9a-f]{2})\s+.+$/i;

  # 存储结果
  my @arpentries;

  # 遍历每个VRF收集ARP条目
  foreach my $vrf_line (@vrfs) {
    my $vrf_name;

    # 获取VRF名称
    if ($vrf_line && $vrf_line =~ m/$vrf_re/) {
      $vrf_name = $1;
    }
    else {
      next;
    }

    # 获取该VRF的IP ARP条目
    my $vrf_cmd = sprintf("show ip arp vrf %s | no-more \n", $vrf_name);
    $expect->send($vrf_cmd);
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);
    my @iparps = split(/\R/, $before);

    # 解析ARP条目
    foreach my $iparp_line (@iparps) {
      if ($iparp_line && $iparp_line =~ m/$iparp_re/) {
        push(@arpentries, {ip => $1, mac => $3});
      }
    }
  }

  return @arpentries;
}

# 从Dell OS10设备收集MAC地址表
# 该方法用于获取交换机的MAC地址表信息，包括VLAN、端口和MAC地址的映射关系
sub macsuck {
  my ($self, $hostlabel, $ssh, $args) = @_;

  debug "$hostlabel $$ macsuck()";

  # 获取MAC地址表
  my $cmds = <<EOF;
show mac address-table | no-more
EOF
  my @data = $ssh->capture({stdin_data => $cmds});
  chomp @data;
  if ($ssh->error) {
    info "$hostlabel $$ SSH命令出错 " . $ssh->error;
    return;
  }

  # OS10 MAC地址表输出格式:
  #hostname# show mac address-table
  #Legend:
  # VlanId        Mac Address         Type        Interface
  # 54            00:00:5e:00:01:36   dynamic     port-channel1
  # 54            00:50:56:af:12:f5   dynamic     port-channel1
  # 54            00:50:56:af:ca:a3   dynamic     port-channel1
  # 54            04:09:73:e3:22:40   dynamic     port-channel17

  # 匹配MAC地址表行的正则表达式
  my $re_mac_line = qr/^(\d+)\s+((([0-9a-f]{2}[:-]){5})[0-9a-f]{2})\s+\w+\s+([a-z]+.*)$/i;
  my $macentries  = {};

  # 解析MAC地址表条目
  foreach my $line (@data) {
    if ($line && $line =~ m/$re_mac_line/) {
      my $port = $5;    # 接口名称
      my $vlan = $1;    # VLAN ID

      # 统计MAC地址条目
      ++$macentries->{$vlan}->{$port}->{mac_as_ieee($2)};
    }
  }

  return $macentries;
}

1;

