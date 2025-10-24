package App::Netdisco::SSHCollector::Platform::IOSXEMac;

=head1 NAME

App::Netdisco::SSHCollector::Platform::IOSXEMac

=head1 DESCRIPTION

Collect MAC address-table entries (FDB) from Cisco IOS-XE via CLI
("show mac address-table"). Intended for platforms where
BRIDGE/Q-BRIDGE MIB does not expose the FDB (e.g. ISR/SD-WAN).

=cut

use strict;
use warnings;

use Dancer ':script';
use Expect;
use NetAddr::MAC qw/mac_as_ieee/;
use Moo;

# Expand short ifName prefixes to full names (kept in sync with IOS.pm)
my $IF_NAME_MAP = {
  Vl  => "Vlan",
  Lo  => "Loopback",
  Fa  => "FastEthernet",
  Gi  => "GigabitEthernet",
  Tw  => "TwoGigabitEthernet",
  Fi  => "FiveGigabitEthernet",
  Te  => "TenGigabitEthernet",
  Twe => "TwentyFiveGigE",
  Fo  => "FortyGigabitEthernet",
  Hu  => "HundredGigE",
  Po  => "Port-channel",
  Bl  => "Bluetooth",
  Wl  => "Wlan-GigabitEthernet",
};

=head2 macsuck($hostlabel, $ssh, $args)

Return a hashref like IOS.pm macsuck:
{ VLAN => { PORTNAME => { MAC_IEEE => 1 } } }

=cut
# 从Cisco IOS-XE设备收集MAC地址表条目
# 该方法用于连接IOS-XE设备并获取其MAC地址表信息
# 适用于BRIDGE/Q-BRIDGE MIB不暴露FDB的平台（如ISR/SD-WAN）
sub macsuck {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ macsuck() via IOSXEMac (Expect)";

    # 打开伪终端连接
    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "无法运行远程命令 [$hostlabel] " . $ssh->error;
        return;
    }
    my $exp = Expect->init($pty);
    my ($pos, $err, $match, $before, $after);

    my $prompt  = qr/[>#]\s*$/;   # IOS-XE执行模式提示符
    my $timeout = 15;

    # 等待提示符出现
    ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

    # 禁用分页显示
    $exp->send("terminal length 0\n");
    ($pos, $err, $match, $before, $after) = $exp->expect($timeout, -re => $prompt);

    # 收集所有条目（动态+静态）
    $exp->send("show mac address-table\n");
    ($pos, $err, $match, $before, $after) = $exp->expect(30, -re => $prompt);

    my @lines = split /\r?\n/, ($before // '');

    # 退出连接
    $exp->send("exit\n");
    $exp->hard_close();

    my $macentries = {};

    # 匹配表行的正则表达式:
    #   VLAN   MAC Address       Type      Ports
    #   10     0011.b908.1dfe    DYNAMIC   Gi0/1/3
    my $re_line = qr{
        ^\s*
        (\S+)                                      # VLAN_ID
        \s+([0-9a-f]{4}\.[0-9a-f]{4}\.[0-9a-f]{4}) # MAC dotted
        \s+(\S+)                                   # TYPE (DYNAMIC/STATIC/etc)
        \s+(\S+)                                   # PORT
        \s*$
    }ix;

    # 解析MAC地址表条目
    LINE: for my $line (@lines) {
        # 跳过标题行和空行
        next if $line =~ /^\s*(Vlan|----|Mac Address Table|Total|$)/i;

        if ($line =~ $re_line) {
            my ($vlan, $mac_dotted, $type, $port_raw) = ($1, $2, uc($3), $4);

            # 只保留数字VLAN，跳过CPU端口
            next LINE unless $vlan =~ /^\d+$/;
            next LINE if uc($port_raw) eq 'CPU';

            # 扩展接口名称
            my ($pfx, $rest) = ($port_raw =~ /^([A-Za-z]+)(.*)$/);
            my $port = defined $pfx
              ? sprintf('%s%s', ($IF_NAME_MAP->{$pfx} || $pfx), ($rest || ''))
              : $port_raw;

            # 将MAC地址转换为冒号分隔的IEEE格式
            my $mac_ieee = mac_as_ieee($mac_dotted);

            # 统计MAC地址条目
            ++$macentries->{$vlan}->{$port}->{$mac_ieee};
        }
    }

    # 输出解析统计信息
    debug "$hostlabel $$ 解析了 "
      . (0 + (map { scalar keys %{ $macentries->{$_} || {} } } keys %$macentries))
      . " 个端口桶 (VLAN: " . join(',', sort keys %$macentries) . ")";

    return $macentries;
}

1;