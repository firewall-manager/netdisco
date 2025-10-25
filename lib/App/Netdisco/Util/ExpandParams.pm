package App::Netdisco::Util::ExpandParams;

# 参数展开工具模块
# CGI::Expand子类，具有类似Rails的参数标记化功能，用于DataTables服务器端处理

use base qw/CGI::Expand/;

use strict;
use warnings;

# 设置最大数组大小（0表示无限制）
sub max_array {0}

# 设置分隔符
sub separator {'.[]'}

# 分割参数名称
# 将参数名称分割为段，支持数组索引语法
sub split_name {
    my $class = shift;
    my $name  = shift;
    $name =~ /^ ([^\[\]\.]+) /xg;
    my @segs = $1;
    push @segs, ( $name =~ / \G (?: \[ ([^\[\]\.]+) \] ) /xg );
    return @segs;
}

# 连接参数名称
# 将参数段连接为完整的参数名称
sub join_name {
    my $class = shift;
    my ( $first, @segs ) = @_;
    return $first unless @segs;
    return "$first\[" . join( '][', @segs ) . "]";
}

1;

__END__

=head1 NAME

App::Netdisco::Util::ExpandParams

=head1 DESCRIPTION

CGI::Expand subclass with Rails like tokenization for parameters passed
during DataTables server-side processing.

=cut
