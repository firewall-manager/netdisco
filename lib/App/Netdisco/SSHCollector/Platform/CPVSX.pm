package App::Netdisco::SSHCollector::Platform::CPVSX;

=head1 NAME

App::Netdisco::SSHCollector::Platform::CPVSX

=head1 DESCRIPTION

Collect ARP entries from Check Point VSX

This collector uses "C<arp>" as the command for the arp utility on your
system. Clish "C<show arp>" does not work correctly in versions prior to R77.30.
Config example:

 device_auth:
   - tag: sshcpvsx
     driver: cli
     platform: CPVSX
     only: '192.0.2.1'
     username: oliver
     password: letmein
     expert_password: letmein2


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

Returns a list of hashrefs in the format C<< { mac => MACADDR, ip => IPADDR } >>.

=back

=cut

# 从Check Point VSX设备收集ARP条目
# 该方法用于连接Check Point VSX设备并获取所有虚拟系统的ARP表信息
# 需要进入专家模式并使用vsenv命令切换虚拟系统
sub arpnip {
    my ($self, $hostlabel, $ssh, $args) = @_;

    my @arpentries = ();

    debug "$hostlabel $$ arpnip()";

    # 打开伪终端连接
    my ($pty, $pid) = $ssh->open2pty;
    unless ($pty) {
        debug "无法运行远程命令 [$hostlabel] " . $ssh->error;
        return ();
    }
    my $expect = Expect->init($pty);

    my ($pos, $error, $match, $before, $after);
    my $prompt;

    # 等待设备提示符
    $prompt = qr/>/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # TODO: 检查CP操作系统版本和VSX状态
    # $expect->send("show vsx\n");
    # ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);
    # debug "$hostlabel $$ show vsx: $before";

    # 枚举虚拟系统
    # 虚拟系统列表格式:
    # VS ID       VS NAME
    # 0           0
    # 1           BACKUP-VSX_xxxxxx_Context
    # ...

    $expect->send("show virtual-system all\n");
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    my @vsxentries = ();
    my @lines = split(m/\n/, $before);

    # 解析虚拟系统列表
    my $linereg = qr/(\d+)\s+([A-Za-z0-9_-]+)/;
    foreach my $line (@lines) {
        if ($line =~ $linereg) {
            my ($vsid, $vsname) = ($1, $2);
            push @vsxentries, { vsid => $vsid,  vsname=> $vsname };
            debug "$hostlabel $$ $vsid, $vsname";
        }
    }

    # TODO: 专家模式仅适用于R77.30之前的版本
    # 对于R77.30及更高版本，可以使用:
    # set virtual-system $vsid
    # show arp dynamic all

    # 进入专家模式
    $expect->send("expert\n");

    # 输入专家密码
    $prompt = qr/Enter expert password:/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    $expect->send( $args->{expert_password} ."\n" );

    # 等待专家模式提示符
    $prompt = qr/#/;
    ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

    # 遍历每个虚拟系统收集ARP条目
    foreach (@vsxentries) {
        my $vsid = $_->{vsid};
        debug "$hostlabel $$ arpnip VSID: $vsid";

        # 切换到指定虚拟系统环境
        $expect->send("vsenv $vsid\n");
        ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

        # 获取ARP表（跳过标题行）
        $expect->send("arp -n | tail -n +2\n");
        ($pos, $error, $match, $before, $after) = $expect->expect(10, -re, $prompt);

        @lines = split(m/\n/, $before);

        # ARP输出格式: 192.168.1.1 ether 00:b6:aa:f5:bb:6e C eth1
        $linereg = qr/([0-9\.]+)\s+ether\s+([a-fA-F0-9:]+)/;

        # 解析ARP条目
        foreach my $line (@lines) {
            if ($line =~ $linereg) {
                my ($ip, $mac) = ($1, $2);
                push @arpentries, { mac => $mac, ip => $ip };
                debug "$hostlabel $$ arpnip VSID: $vsid IP: $ip MAC: $mac";
            }
        }

    }

    # 退出专家模式
    $expect->send("exit\n");

    # 等待设备提示符
    $prompt = qr/>/;
    ($pos, $error, $match, $before, $after) = $expect->expect(5, -re, $prompt);

    # 退出连接
    $expect->send("exit\n");

    $expect->soft_close();

    return @arpentries;
}

1;
