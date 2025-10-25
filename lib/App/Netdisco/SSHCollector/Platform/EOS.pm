package App::Netdisco::SSHCollector::Platform::EOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::EOS

=head1 DESCRIPTION

Collect ARP entries from Arista EOS devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use NetAddr::MAC qw/mac_as_ieee/;
use JSON         qw(decode_json);

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

my $if_name_map = {Vl => "Vlan", Lo => "Loopback", Eth => "Ethernet", Po => "Port-channel",};

# 从Arista EOS设备收集ARP条目
# 该方法用于连接Arista EOS交换机并获取所有VRF的IPv4 ARP和IPv6邻居信息
# 使用JSON格式输出，支持多VRF环境
sub arpnip {
  my ($self, $hostlabel, $ssh, $args) = @_;
  debug "$hostlabel $$ arpnip()";

  my @arpentries;

  # ----- 收集IPv4 ARP条目 -----
  my $cmd_v4 = "show ip arp vrf all | json | no-more\n";
  my @out_v4 = $ssh->capture({stdin_data => $cmd_v4});
  if (!$ssh->error) {
    my $data = eval { decode_json(join '', @out_v4) };
    if ($data && $data->{vrfs}) {

      # 遍历所有VRF
      foreach my $vrf (values %{$data->{vrfs}}) {
        next unless $vrf->{ipV4Neighbors};

        # 遍历每个IPv4邻居
        foreach my $n (@{$vrf->{ipV4Neighbors}}) {
          next unless $n->{address} && $n->{hwAddress};

          # 某些条目有多个接口: "Vlan3134, Port-Channel46"
          my @ifaces = split /\s*,\s*/, ($n->{interface} // '');
          foreach my $iface (@ifaces) {
            push @arpentries, {ip => $n->{address}, mac => $n->{hwAddress}, ($iface ? (iface => $iface) : ()),};
          }
        }
      }
    }
  }
  else {
    info "$hostlabel $$ 运行ARP命令时出错: " . $ssh->error;
  }

  # ----- 收集IPv6邻居条目 -----
  my $cmd_v6 = "show ipv6 neighbor vrf all | json | no-more\n";
  my @out_v6 = $ssh->capture({stdin_data => $cmd_v6});
  if (!$ssh->error) {
    my $data = eval { decode_json(join '', @out_v6) };
    if ($data && $data->{vrfs}) {

      # 遍历所有VRF
      foreach my $vrf (values %{$data->{vrfs}}) {
        next unless $vrf->{ipV6Neighbors};

        # 遍历每个IPv6邻居
        foreach my $n (@{$vrf->{ipV6Neighbors}}) {
          next unless $n->{address} && $n->{hwAddress};
          push @arpentries, {ip => $n->{address}, mac => $n->{hwAddress}};
        }
      }
    }
  }
  else {
    info "$hostlabel $$ 运行IPv6邻居命令时出错: " . $ssh->error;
  }

  return @arpentries;
}

# 从Arista EOS设备收集MAC地址表
# 该方法用于获取交换机的MAC地址表信息，包括VLAN、端口和MAC地址的映射关系
sub macsuck {
  my ($self, $hostlabel, $ssh, $args) = @_;

  unless ($ssh) {
    info "$hostlabel $$ macsuck() - 没有SSH会话";
    return;
  }

  debug "$hostlabel $$ macsuck()";

  # 获取MAC地址表的JSON输出
  my $cmd = "show mac address-table | json | no-more\n";
  my @out = $ssh->capture({stdin_data => $cmd});
  if ($ssh->error) {
    info "$hostlabel $$ 运行命令时出错: " . $ssh->error;
    return;
  }

  my $json = join '', @out;
  my $data = eval { decode_json($json) };
  if ($@ or not $data->{unicastTable}->{tableEntries}) {
    info "$hostlabel $$ 解析JSON失败: $@";
    return;
  }

  my $macentries = {};

  # 解析MAC地址表条目
  foreach my $entry (@{$data->{unicastTable}->{tableEntries}}) {
    my $vlan = $entry->{vlanId} // 0;                # VLAN ID，默认为0
    my $mac  = mac_as_ieee($entry->{macAddress});    # 转换为IEEE格式的MAC地址
    my $port = $entry->{interface};                  # 接口名称

    # 跳过无效或无端口的条目
    next unless $mac && $port && $port ne 'Router';

    # 统计MAC地址条目
    ++$macentries->{$vlan}->{$port}->{$mac};

    debug sprintf "解析MAC vlan=%s mac=%s port=%s type=%s", $vlan, $mac, $port, $entry->{entryType};
  }

  return $macentries;
}

# 从Arista EOS设备收集子网信息
# 该方法用于获取所有VRF的直连路由，用于确定设备的子网范围
sub subnets {
  my ($self, $hostlabel, $ssh, $args) = @_;
  debug "$hostlabel $$ subnets()";

  # 获取所有VRF的直连路由
  my $cmd = "show ip route vrf all connected | json | no-more\n";
  my @out = $ssh->capture({stdin_data => $cmd});
  if ($ssh->error) {
    info "$hostlabel $$ 运行路由命令时出错: " . $ssh->error;
    return;
  }

  my $data = eval { decode_json(join '', @out) };
  if ($@ or not $data->{vrfs}) {
    info "$hostlabel $$ 解析JSON路由失败: $@";
    return;
  }

  my @subnets;

  # 遍历所有VRF的路由
  foreach my $vrf (values %{$data->{vrfs}}) {
    foreach my $cidr (keys %{$vrf->{routes}}) {
      next if $cidr =~ m/\/32$/;    # 跳过主机路由
                                    # 只添加有效的子网（IPv4格式）
      push @subnets, $cidr if $cidr =~ m{^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$};
    }
  }

  return @subnets;
}

1;
