package App::Netdisco::AnyEvent::Nbtstat;

# 异步NetBIOS节点状态请求器
# 使用AnyEvent框架进行异步NetBIOS查询

use strict;
use warnings;

use Socket qw(AF_INET SOCK_DGRAM inet_aton sockaddr_in);
use List::Util ();
use Carp       ();

use AnyEvent::Loop;
use AnyEvent (); BEGIN { AnyEvent::common_sense }
use AnyEvent::Util ();

# 构造函数
# 创建异步NetBIOS查询器实例
sub new {
    my ( $class, %args ) = @_;

    my $interval = $args{interval};
    # 此默认值应该每秒生成约50个请求
    $interval = 0.2 unless defined $interval;

    my $timeout = $args{timeout};

    # 根据RFC1002，超时应该是250ms，但我们要加倍
    $timeout = 0.5 unless defined $timeout;

    my $self = bless { interval => $interval, timeout => $timeout, %args },
        $class;

    Scalar::Util::weaken( my $wself = $self );

    socket my $fh4, AF_INET, Socket::SOCK_DGRAM(), 0
        or Carp::croak "Unable to create socket : $!";

    AnyEvent::Util::fh_nonblocking $fh4, 1;
    $self->{fh4} = $fh4;
    $self->{rw4} = AE::io $fh4, 0, sub {
        if ( my $peer = recv $fh4, my $resp, 2048, 0 ) {
            $wself->_on_read( $resp, $peer );
        }
    };

    # NetBIOS查询任务
    $self->{_tasks} = {};

    return $self;
}

# 间隔时间访问器
# 获取或设置请求间隔时间
sub interval { @_ > 1 ? $_[0]->{interval} = $_[1] : $_[0]->{interval} }

# 超时时间访问器
# 获取或设置请求超时时间
sub timeout { @_ > 1 ? $_[0]->{timeout} = $_[1] : $_[0]->{timeout} }

# NetBIOS节点状态查询
# 对指定主机执行NetBIOS节点状态请求
sub nbtstat {
    my ( $self, $host, $cb ) = @_;

    my $ip   = inet_aton($host);
    my $port = 137;

    my $request = {
        host        => $host,
        results     => {},
        cb          => $cb,
        destination => scalar sockaddr_in( $port, $ip ),
    };

    $self->{_tasks}{ $request->{destination} } = $request;

    my $delay = $self->interval * scalar keys %{ $self->{_tasks} || {} };

    # 可能有一种更好的节流发送方式
    # 但这现在可以工作，因为我们目前不支持重试
    my $w; $w = AE::timer $delay, 0, sub {
        undef $w;
        $self->_send_request($request);
    };

    return $self;
}

# 读取响应处理
# 处理从套接字接收到的NetBIOS响应
sub _on_read {
    my ( $self, $resp, $peer ) = @_;

    ($resp) = $resp =~ /^(.*)$/s
        if AnyEvent::TAINT && $self->{untaint};

    # 查找我们的任务
    my $request = $self->{_tasks}{$peer};

    return unless $request;

    $self->_store_result( $request, 'OK', $resp );

    return;
}

# 存储结果
# 解析NetBIOS响应并存储结果
sub _store_result {
    my ( $self, $request, $status, $resp ) = @_;

    my $results = $request->{results};

    my @rr          = ();
    my $mac_address = "";

    if ( $status eq 'OK' && length($resp) > 56 ) {
        my $num_names = unpack( "C", substr( $resp, 56 ) );
        my $name_data = substr( $resp, 57 );

        for ( my $i = 0; $i < $num_names; $i++ ) {
            my $rr_data = substr( $name_data, 18 * $i, 18 );
            push @rr, _decode_rr($rr_data);
        }

        $mac_address = join "-",
            map { sprintf "%02X", $_ }
            unpack( "C*", substr( $name_data, 18 * $num_names, 6 ) );
        $results = {
            'status'      => 'OK',
            'names'       => \@rr,
            'mac_address' => $mac_address
        };
    }
    elsif ( $status eq 'OK' ) {
        $results = { 'status' => 'SHORT' };
    }
    else {
        $results = { 'status' => $status };
    }

    # 清除请求特定数据
    delete $request->{timer};

    # 清理
    delete $self->{_tasks}{ $request->{destination} };

    # 完成
    $request->{cb}->($results);

    undef $request;

    return;
}

# 发送请求
# 构造并发送NetBIOS节点状态查询请求
sub _send_request {
    my ( $self, $request ) = @_;

    my $msg = "";
    # 我们使用进程ID作为标识符字段，因为不需要
    # 在查询的主机/端口之外唯一响应
    $msg .= pack( "n*", $$, 0, 1, 0, 0, 0 );
    $msg .= _encode_name( "*", "\x00", 0 );
    $msg .= pack( "n*", 0x21, 0x0001 );

    $request->{start} = time;

    $request->{timer} = AE::timer $self->timeout, 0, sub {
        $self->_store_result( $request, 'TIMEOUT' );
    };

    my $fh = $self->{fh4};

    send $fh, $msg, 0, $request->{destination}
        or $self->_store_result( $request, 'ERROR' );

    return;
}

# 编码名称
# 将NetBIOS名称编码为NetBIOS格式
sub _encode_name {
    my $name   = uc(shift);
    my $pad    = shift || "\x20";
    my $suffix = shift || 0x00;

    $name .= $pad x ( 16 - length($name) );
    substr( $name, 15, 1, chr( $suffix & 0xFF ) );

    my $encoded_name = "";
    for my $c ( unpack( "C16", $name ) ) {
        $encoded_name .= chr( ord('A') + ( ( $c & 0xF0 ) >> 4 ) );
        $encoded_name .= chr( ord('A') + ( $c & 0xF ) );
    }

    # 注意_encode_name函数不添加任何作用域，
    # 也不计算长度（32），它只是添加前缀
    return "\x20" . $encoded_name . "\x00";
}

# 解码资源记录
# 解析NetBIOS资源记录数据
sub _decode_rr {
    my $rr_data = shift;

    my @nodetypes = qw/B-node P-node M-node H-node/;
    my ( $name, $suffix, $flags ) = unpack( "a15Cn", $rr_data );
    $name =~ tr/\x00-\x19/\./;    # 将控制字符替换为"."
    $name =~ s/\s+//g;

    my $rr = {};
    $rr->{'name'}   = $name;
    $rr->{'suffix'} = $suffix;
    $rr->{'G'}      = ( $flags & 2**15 ) ? "GROUP" : "UNIQUE";
    $rr->{'ONT'}    = $nodetypes[ ( $flags >> 13 ) & 3 ];
    $rr->{'DRG'}    = ( $flags & 2**12 ) ? "Deregistering" : "Registered";
    $rr->{'CNF'}    = ( $flags & 2**11 ) ? "Conflict" : "";
    $rr->{'ACT'}    = ( $flags & 2**10 ) ? "Active" : "Inactive";
    $rr->{'PRM'}    = ( $flags & 2**9 ) ? "Permanent" : "";

    return $rr;
}

1;
__END__

=head1 NAME

App::Netdisco::AnyEvent::Nbtstat - Request NetBIOS node status with AnyEvent

=head1 SYNOPSIS

    use App::Netdisco::AnyEvent::Nbtstat;;

    my $request = App::Netdisco::AnyEvent::Nbtstat->new();

    my $cv = AE::cv;

    $request->nbtstat(
        '127.0.0.1',
        sub {
            my $result = shift;
            print "MAC: ", $result->{'mac_address'} || '', " ";
            print "Status: ", $result->{'status'}, "\n";
            printf '%3s %-18s %4s %-18s', '', 'Name', '', 'Type'
                if ( $result->{'status'} eq 'OK' );
            print "\n";
            for my $rr ( @{ $result->{'names'} } ) {
                printf '%3s %-18s <%02s> %-18s', '', $rr->{'name'},
                    $rr->{'suffix'},
                    $rr->{'G'};
                print "\n";
            }
            $cv->send;
        }
    );

    $cv->recv;

=head1 DESCRIPTION

L<App::Netdisco::AnyEvent::Nbtstat> is an asynchronous AnyEvent NetBIOS node
status requester.

=head1 ATTRIBUTES

L<App::Netdisco::AnyEvent::Nbtstat> implements the following attributes.

=head2 C<interval>

    my $interval = $request->interval;
    $request->interval(1);

Interval between requests, defaults to 0.02 seconds.

=head2 C<timeout>

    my $timeout = $request->timeout;
    $request->timeout(2);

Maximum request response time, defaults to 0.5 seconds.

=head1 METHODS

L<App::Netdisco::AnyEvent::Nbtstat> implements the following methods.

=head2 C<nbtstat>

    $request->nbtstat($ip, sub {
        my $result = shift;
    });

Perform a NetBIOS node status request of $ip.

=head1 SEE ALSO

L<AnyEvent>

=cut
