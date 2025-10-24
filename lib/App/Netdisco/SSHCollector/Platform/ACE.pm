package App::Netdisco::SSHCollector::Platform::ACE;

=head1 NAME

App::Netdisco::SSHCollector::Platform::ACE

=head1 DESCRIPTION

Collect ARP entries from Cisco ACE load balancers. ACEs have multiple
virtual contexts with individual ARP tables. Contexts are enumerated
with C<show context>, afterwards the commands C<changeto CONTEXTNAME> and
C<show arp> must be executed for every context.

The IOS shell does not permit to combine multiple commands in a single
line, and Net::OpenSSH uses individual connections for individual commands,
so we need to use Expect to execute the changeto and show commands in
the same context.

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

# 从Cisco ACE负载均衡器收集ARP条目
# ACE设备有多个虚拟上下文，每个上下文都有独立的ARP表
# 需要先枚举所有上下文，然后为每个上下文执行changeto和show arp命令
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
    my $prompt = qr/#/;  # 匹配设备提示符

    # 等待设备提示符出现
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # 禁用分页显示
    $expect->send("terminal length 0\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    # 获取所有上下文名称
    $expect->send("show context | include Name\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    my @ctx;        # 存储上下文名称
    my @arpentries; # 存储ARP条目

    # 解析上下文名称并收集每个上下文的ARP条目
    for (split(/\n/, $before)){
        if (m/Name: (\S+)/){
            push(@ctx, $1);
            # 切换到指定上下文
            $expect->send("changeto $1\n");
            ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);
            # 获取该上下文的ARP表
            $expect->send("show arp\n");
            ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);
            # 解析ARP输出
            for (split(/\n/, $before)){
                my ($ip, $mac) = split(/\s+/);
                # 验证IP和MAC地址格式
                if ($ip =~ m/(\d{1,3}\.){3}\d{1,3}/ && $mac =~ m/[0-9a-f.]+/i) {
                    push(@arpentries, { ip => $ip, mac => $mac });
                }
            }

        }
    }

    # 退出连接
    $expect->send("exit\n");
    $expect->soft_close();

    return @arpentries;
}

1;
