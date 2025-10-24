package App::Netdisco::SSHCollector::Platform::FortiOS;

=head1 NAME

App::Netdisco::SSHCollector::Platform::FortiOS

=head1 DESCRIPTION

Collect ARP entries from Fortinet FortiOS Fortigate devices.

=cut

use strict;
use warnings;

use Dancer ':script';
use Moo;
use Expect;
use Regexp::Common qw(net);

=head1 PUBLIC METHODS

=over 4

=item B<arpnip($host, $ssh)>

Retrieve ARP entries from device. C<$host> is the hostname or IP address
of the device. C<$ssh> is a Net::OpenSSH connection to the device.

If a post-login banner needs to be accepted, please set C<$banner> to true.

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

my $prompt = qr/ [\$#] +$/;
my $more_pattern = qr/--More--/;
my $timeout = 10;

# 获取分页输出的辅助方法
# 该方法用于处理FortiOS设备的分页输出，自动处理"--More--"提示
sub get_paginated_output {
    my ($command, $expect) = @_;
    my $more_flag = 0;
    my @lines = undef;
    my @alllines = undef;
    $expect->send($command."\n");
    while (1) {
        my ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt, -re, $more_pattern);
        if ($match) {
            if ($match =~ $more_pattern) {
                $more_flag = 1;
                @lines = split(/\R/, $before);
                push(@alllines, grep {$_ =~ /\S/} @lines);
                debug("跳过--More--分页");
                $expect->send(" ");  # 发送空格继续
            } elsif ($match =~ $prompt) {
                $more_flag = 0;
                @lines = split(/\R/, $before);
                push(@alllines, grep {$_ =~ /\S/} @lines);
                foreach my $line (@alllines) {
                    debug("收集的输出: $line") if $line;
                }
                last;
            }
        }
    }

    return @alllines;
}

# 在指定上下文中收集ARP条目
# 该方法用于在FortiOS设备的特定VDOM上下文中收集IPv4 ARP和IPv6邻居条目
sub arpnip_context {
    my ($expect, $prompt, $timeout, $arpentries) = @_;

    # IPv4 ARP收集
    ##########

    my @data = get_paginated_output("get system arp", $expect);

    # FortiOS ARP输出格式:
    # fortigate # get system arp
    # Address           Age(min)   Hardware Addr      Interface
    # 2.6.0.5     0          00:40:46:f9:63:0f PLAY-0400
    # 1.2.9.7      2          00:30:59:bc:f6:94 DEAD-3550

    my $re_ipv4_arp = qr/^($RE{net}{IPv4})\s*\d+\s*($RE{net}{MAC})\s*\S+$/;
    foreach (@data) {
        if ($_ && /$re_ipv4_arp/) {
            debug "\t找到IPv4: $1 => MAC: $2";
            push(@$arpentries, { ip => $1, mac => $2 });
        }
    }

    # IPv6邻居发现收集
    ##########

    @data = get_paginated_output("diagnose ipv6 neighbor-cache list", $expect);

    # FortiOS IPv6邻居缓存输出格式:
    # fortigate # diagnose ipv6 neighbor-cache list
    # ifindex=403 ifname=WORK-4016 fe80::abcd:1234:dead:f00d ab:cd:ef:01:23:45 state=00000004 use=42733 confirm=42733 update=41100 ref=3
    # ifindex=67 ifname=PLAY-4036 ff02::16 33:33:00:00:00:16 state=00000040 use=4765 confirm=10765 update=4765 ref=0
    # ifindex=28 ifname=root :: 00:00:00:00:00:00 state=00000040 use=589688110 confirm=589694110 update=589688110 ref=1
    # ifindex=48 ifname=FUN-4024 2001:42:1234:fe80:1234:1234:1234:1234 b0:c1:e2:f3:a4:b5 state=00000008 use=12 confirm=2 update=12 ref=2

    # 可能失败并显示: Unknown action 0 - 这是登录用户权限问题

    my $re_ipv6_arp = qr/^ifindex=\d+\s+ifname=\S+\s+($RE{net}{IPv6}{-sep => ':'}{-style => 'HeX'})\s+($RE{net}{MAC}).*$/;
    foreach (@data) {
        if ($_ && /$re_ipv6_arp/) {
            debug "\t找到IPv6: $1 => MAC: $2";
            push(@$arpentries, { ip => $1, mac => $2 });
        }
    }
}

# 从Fortinet FortiOS FortiGate设备收集ARP条目
# 该方法用于连接FortiGate防火墙并获取其ARP表信息
# 支持多VDOM环境，需要遍历所有VDOM并收集每个VDOM的ARP信息
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    debug "$hostlabel $$ arpnip()";

    # 打开伪终端连接
    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        warn "无法运行远程命令 [$hostlabel] " . $ssh->error;
        return ();
    }

    # 禁用Expect调试输出
    $Expect::Debug = 0;
    $Expect::Exp_Internal = 0;

    my $expect = Expect->init($pty);
    $expect->raw_pty(1);

    my ($pos, $error, $match, $before, $after);

    # 如果需要接受登录横幅
    if ($args->{banner}) {
        my $banner = qr/^\(Press 'a' to accept\):/;
        ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $banner);

        $expect->send("a");
    }
    ($pos, $error, $match, $before, $after) = $expect->expect($timeout, -re, $prompt);

    # 检查是否为多VDOM配置
    my @data = get_paginated_output("get system status", $expect);
    my $multi_vdom = 0;
    foreach (@data) {
        if ($_ && /^Virtual domain configuration: (multiple|split-task)$/) {
            $multi_vdom = 1;
        last;
        }
    }
    my $arpentries = [];
    if ($multi_vdom) {
        # 多VDOM环境，需要遍历所有VDOM
        $expect->send("config global\n");
        $expect->expect($timeout, -re, $prompt);

        # 获取所有VDOM列表
        my @data = get_paginated_output("get system vdom-property", $expect);
        my $vdoms = [];
        foreach (@data) {
            push(@$vdoms, $1) if $_ && (/^==\s*\[\s*(\S+)\s*\]$/);
        }

        $expect->send("end\n");
        $expect->expect($timeout, -re, $prompt);

        # 遍历每个VDOM收集ARP条目
        foreach (@$vdoms) {
            $expect->send("config vdom\n");
            $expect->expect($timeout, -re, $prompt);
            $expect->send("edit $_\n");
            debug ("切换到配置VDOM; 编辑 $_");
            $expect->expect($timeout, -re, $prompt);
            arpnip_context($expect, $prompt, $timeout, $arpentries);
            $expect->send("end\n");
            $expect->expect($timeout, -re, $prompt);
        }
    } else {
        # 单VDOM环境，直接收集ARP条目
        arpnip_context($expect, $prompt, $timeout, $arpentries);
    }
    # 退出连接
    $expect->send("exit\n");
    $expect->soft_close();

    return @$arpentries;
}

1;
