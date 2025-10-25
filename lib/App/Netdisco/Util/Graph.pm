package App::Netdisco::Util::Graph;

# 图形工具模块
# 从Netdisco数据生成GraphViz输出

use App::Netdisco;

use Dancer qw/:syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::DNS qw/hostname_from_ip ipv4_from_hostname/;
use Graph::Undirected ();
use GraphViz ();

use base 'Exporter';
our @EXPORT = ('graph');
our @EXPORT_OK = qw/
  graph_each
  graph_addnode
  make_graph
/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# 全局变量，用于图形生成
our ($ip, $label, $isdev, $devloc, %GRAPH, %GRAPH_SPEED);

=head1 NAME

App::Netdisco::Util::Graph

=head1 SYNOPSIS

 $ brew install graphviz   <-- install graphviz on your system
 
 $ ~/bin/localenv bash
 $ cpanm --notest Graph GraphViz
 $ mkdir ~/graph
 
 use App::Netdisco::Util::Graph;
 graph;

=head1 DESCRIPTION

Generate GraphViz output from Netdisco data. Requires that the L<Graph> and
L<GraphViz> distributions be installed.

Requires the same config as for Netdisco 1, but within a C<graph> key.  See
C<share/config.yml> in the source distribution for an example.

The C<graph> subroutine is exported by default. The C<:all> tag will export
all subroutines.

=head1 EXPORT

=over 4

=item graph()

Creates netmap of network.

=back

=cut

# 创建网络图形
# 创建网络的地图
sub graph {
    my %CONFIG = %{ setting('graph') };

    # 获取当前时间信息
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my $month = sprintf("%d%02d",$year+1900,$mon+1);

    info "graph() - Creating Graphs";
    my $G = make_graph();

    unless (defined $G){
        print "graph() - make_graph() failed.  Try running with debug (-D).\n";
        return;
    }

    # 获取连通组件
    my @S = $G->connected_components;

    # 计算每个子图中的节点数量
    my %S_count;
    for (my $i=0;$i< scalar @S;$i++){
        $S_count{$i} = scalar @{$S[$i]};
    }

    # 按节点数量排序处理子图
    foreach my $subgraph (sort { $S_count{$b} <=> $S_count{$a} } keys %S_count){
        my $SUBG = $G->copy;
        print "\$S[$subgraph] has $S_count{$subgraph} nodes.\n";

        # 从此子图中移除其他子图
        my %S_notme = %S_count;
        delete $S_notme{$subgraph};
        foreach my $other (keys %S_notme){
            print "Removing Non-connected nodes: ",join(',',@{$S[$other]}),"\n";
            $SUBG->delete_vertices(@{$S[$other]})
        }

        # 创建子图
        my $timeout = defined $CONFIG{graph_timeout} ? $CONFIG{graph_timeout} : 60;

        eval {
            alarm($timeout*60);
            graph_each($SUBG,'');
            alarm(0);
        };
        if ($@) {
            if ($@ =~ /timeout/){
                print "! Creating Graph timed out!\n";
            } else {
                print "\n$@\n";
            }
        }

        # 为每个非连通的网络段创建子图的设施
        # 现在，让我们只创建最大的一个
        last;
    }
}

=head1 EXPORT_OK

=over 4

=item graph_each($graph_obj, $name)

Generates subgraph. Does actual GraphViz calls.

=cut

# 生成子图
# 执行实际的GraphViz调用
sub graph_each  {
    my ($G, $name) = @_;
    my %CONFIG = %{ setting('graph') };
    info "Creating new Graph";

    # 图形定义
    my $graph_defs = {
                     'bgcolor' => $CONFIG{graph_bg}         || 'black',
                     'color'   => $CONFIG{graph_color}      || 'white',
                     'overlap' => $CONFIG{graph_overlap}    || 'scale',
                     'fontpath'=> _homepath('graph_fontpath',''),
                     'ranksep' => $CONFIG{graph_ranksep}    || 0.3,
                     'nodesep' => $CONFIG{graph_nodesep}    || 2,
                     'ratio'   => $CONFIG{graph_ratio}      || 'compress',
                     'splines' => ($CONFIG{graph_splines} ? 'true' : 'false'),
                     'fontcolor' => $CONFIG{node_fontcolor} || 'white',
                     'fontname'  => $CONFIG{node_font}      || 'lucon',
                     'fontsize'  => $CONFIG{node_fontsize}  || 12,
                     };
    # 边定义
    my $edge_defs  = {
                     'color' => $CONFIG{edge_color}         || 'wheat',
                     };
    # 节点定义
    my $node_defs  = {
                     'shape'     => $CONFIG{node_shape}     || 'box',
                     'fillcolor' => $CONFIG{node_fillcolor} || 'dimgrey',
                     'fontcolor' => $CONFIG{node_fontcolor} || 'white',
                     'style'     => $CONFIG{node_style}     || 'filled',
                     'fontname'  => $CONFIG{node_font}      || 'lucon',
                     'fontsize'  => $CONFIG{node_fontsize}  || 12,
                     'fixedsize' => ($CONFIG{node_fixedsize} ? 'true' : 'false'),
                     };
    $node_defs->{height} = $CONFIG{node_height} if defined $CONFIG{node_height};
    $node_defs->{width}  = $CONFIG{node_width}  if defined $CONFIG{node_width};

    # 设置epsilon值
    my $epsilon = undef;
    if (defined $CONFIG{graph_epsilon}){
        $epsilon = "0." . '0' x $CONFIG{graph_epsilon} . '1';
    }

    # GraphViz配置
    my %gv = (
               directed => 0,
               layout   => $CONFIG{graph_layout} || 'twopi',
               graph    => $graph_defs,
               node     => $node_defs,
               edge     => $edge_defs,
               width    => $CONFIG{graph_x}      || 30,
               height   => $CONFIG{graph_y}      || 30,
               epsilon  => $epsilon,
              );

    my $gv = GraphViz->new(%gv);

    # 创建节点映射
    my %node_map = ();
    my @nodes = $G->vertices;

    # 为每个设备添加节点
    foreach my $dev (@nodes){
        my $node_name = graph_addnode($gv,$dev);
        $node_map{$dev} = $node_name;
    }

    # 设置根设备
    my $root_ip = defined $CONFIG{root_device}
      ? (ipv4_from_hostname($CONFIG{root_device}) || $CONFIG{root_device})
      : undef;

    if (defined $root_ip and defined $node_map{$root_ip}){
        my $gv_root_name = $gv->_quote_name($root_ip);
        if (defined $gv_root_name){
            $gv->{GRAPH_ATTRS}->{root}=$gv_root_name;
        }
    }

    # 处理边（连接）
    my @edges = $G->edges;

    while (my $e = shift @edges){
        my $link = $e->[0];
        my $dest = $e->[1];
        my $speed = $GRAPH_SPEED{$link}->{$dest}->{speed};

        if (!defined($speed)) {
            info "  ! No link speed for $link -> $dest";
            $speed = 0;
        }

        my %edge = ();
        my $val = ''; my $suffix = '';

        # 解析速度值
        if ($speed =~ /^([\d.]+)\s+([a-z])bps$/i) {
            $val = $1; $suffix = $2;
        }

        # 根据速度设置边样式
        if ( ($suffix eq 'k') or ($speed =~ m/(t1|ds3)/i) ){
            $edge{color} = 'green';
            $edge{style} = 'dotted';
        }

        if ($suffix eq 'M'){
            if ($val < 10.0){
                $edge{color} = 'green';
                $edge{style} = 'dashed';
            } elsif ($val < 100.0){
                $edge{color} = '#8b7e66';
                $edge{style} = 'solid';
            } else {
                $edge{color} = '#ffe7ba';
                $edge{style} = 'solid';
            }
        }

        if ($suffix eq 'G'){
            $edge{color} = 'cyan1';
        }

        # 添加额外的边样式（主要用于修改宽度）
        if(defined $CONFIG{edge_style}) {
            $edge{style} .= "," . $CONFIG{edge_style};
        }

        $gv->add_edge($link => $dest, %edge );
    }

    info "Ignore all warnings about node size";

    # 生成各种格式的图形文件
    if (defined $CONFIG{graph_raw} and $CONFIG{graph_raw}){
        my $graph_raw = _homepath('graph_raw');
        info "  Creating raw graph: $graph_raw";
        $gv->as_canon($graph_raw);
    }

    if (defined $CONFIG{graph} and $CONFIG{graph}){
        my $graph_gif = _homepath('graph');
        info "  Creating graph: $graph_gif";
        $gv->as_gif($graph_gif);
    }

    if (defined $CONFIG{graph_png} and $CONFIG{graph_png}){
        my $graph_png = _homepath('graph_png');
        info "  Creating png graph: $graph_png";
        $gv->as_png($graph_png);
    }

    if (defined $CONFIG{graph_map} and $CONFIG{graph_map}){
        my $graph_map = _homepath('graph_map');
        info "  Creating CMAP : $graph_map";
        $gv->as_cmap($graph_map);
    }

    if (defined $CONFIG{graph_svg} and $CONFIG{graph_svg}){
        my $graph_svg = _homepath('graph_svg');
        info "  Creating SVG : $graph_svg";
        $gv->as_svg($graph_svg);
    }
}

=item graph_addnode($graphviz_obj, $node_ip)

Checks for mapping settings in config file and adds node to the GraphViz
object.

=cut

# 添加节点到GraphViz对象
# 检查配置文件中的映射设置并将节点添加到GraphViz对象
sub graph_addnode {
    my $gv = shift;
    my %CONFIG = %{ setting('graph') };
    my %node = ();

    $ip     = shift;
    $label  = $GRAPH{$ip}->{dns};
    $isdev  = $GRAPH{$ip}->{isdev};
    $devloc = $GRAPH{$ip}->{location};

    $label = "($ip)" unless defined $label;
    my $domain_suffix = setting('domain_suffix');
    $label =~ s/$domain_suffix//;
    $node{label} = $label;

    # 下面的按名称解引用标量
    #   要求变量是非词法作用域的（不是my）
    #   我们将创建一些本地非词法作用域版本
    #   它们将在此块结束时过期
    # 节点映射
    foreach my $map (@{ $CONFIG{'node_map'} || [] }){
        my ($var, $regex, $attr, $val) = split(':', $map);

        { no strict 'refs';
           $var = ${"$var"};
        }
        next unless defined $var;

        if ($var =~ /$regex/) {
            debug "  graph_addnode - Giving node $ip $attr = $val";
            $node{$attr} = $val;
        }
    }

    # 图像映射的URL（非根托管的修复）
    if ($isdev) {
        $node{URL} = "/device?&q=$ip";
    }
    else {
        $node{URL} = "/search?tab=node&q=$ip";
        # 覆盖上面给节点的任何颜色。Bug 1094208
        $node{fillcolor} = $CONFIG{'node_problem'} || 'red';
    }

    # 处理图形集群
    if ($CONFIG{'graph_clusters'} && $devloc) {
        # 这个奇怪的构造解决了GraphViz.pm中
        # 集群名称引用的bug。如果名称包含空格，
        # 它只会引用它，导致创建子图名称
        # cluster_"location with spaces"。根据dot语法这是非法名称，
        # 所以如果名称匹配有问题的正则表达式，
        # 我们通过在名称前加空格让GraphViz.pm生成内部名称。
        #
        # 这是rt.cpan.org的bug ID 16912 -
        # http://rt.cpan.org/NoAuth/Bug.html?id=16912
        #
        # 另一个bug，ID 11514，阻止我们使用名称和标签属性的组合
        # 来向用户隐藏额外的空格。但是，由于只是一个空格，
        # 希望不会太明显。
        my($loc) = $devloc;
        $loc = " " . $loc if ($loc =~ /^[a-zA-Z](\w| )*$/);
        $node{cluster} = { name => $loc };
    }

    my $rv = $gv->add_node($ip, %node);
    return $rv;
}

=item make_graph()

Returns C<Graph::Undirected> object that represents the discovered network.

Graph is made by loading all the C<device_port> entries that have a neighbor,
using them as edges. Then each device seen in those entries is added as a
vertex.

Nodes without topology information are not included.

=back

=cut

# 创建图形对象
# 返回表示已发现网络的Graph::Undirected对象
sub make_graph {
    my $G = Graph::Undirected->new();

    # 获取设备和链接信息
    my $devices = schema(vars->{'tenant'})->resultset('Device')
        ->search({}, { columns => [qw/ip dns location /] });
    my $links = schema(vars->{'tenant'})->resultset('DevicePort')
        ->search({remote_ip => { -not => undef }},
                 { columns => [qw/ip remote_ip speed remote_type/]});
    my %aliases = map {$_->alias => $_->ip}
        schema(vars->{'tenant'})->resultset('DeviceIp')
          ->search({}, { columns => [qw/ip alias/] })->all;

    my %devs = ( map {($_->ip => $_->dns)}      $devices->all );
    my %locs = ( map {($_->ip => $_->location)} $devices->all );

    # 检查是否有拓扑信息
    unless ($links->count > 0) {
        debug "make_graph() - No topology information. skipping.";
        return undef;
    }

    my %link_seen = ();
    my %linkmap   = ();

    # 处理每个链接
    while (my $link = $links->next) {
        my $source = $link->ip;
        my $dest   = $link->remote_ip;
        my $speed  = $link->speed;
        my $type   = $link->remote_type;

        # 检查别名
        if (defined $aliases{$dest}) {
            # 设置为根设备
            $dest = $aliases{$dest};
        }

        # 移除回环 - 在别名检查之后
        if ($source eq $dest) {
            debug "  make_graph() - Loopback on $source";
            next;
        }

        # 跳过IP电话
        if (defined $type and $type =~ /ip.phone/i) {
            debug "  make_graph() - Skipping IP Phone. $source -> $dest ($type)";
            next;
        }
        next if exists $link_seen{$source}->{$dest};

        push(@{ $linkmap{$source} }, $dest);

        # 处理反向链接
        $link_seen{$source}->{$dest}++;
        $link_seen{$dest}->{$source}++;

        $GRAPH_SPEED{$source}->{$dest}->{speed}=$speed;
        $GRAPH_SPEED{$dest}->{$source}->{speed}=$speed;
    }

    # 构建图形
    foreach my $link (keys %linkmap) {
        foreach my $dest (@{ $linkmap{$link} }) {

            # 为每个端点添加顶点
            foreach my $side ($link, $dest) {
                unless (defined $GRAPH{$side}) {
                    my $is_dev = exists $devs{$side};
                    my $dns = $is_dev ?
                              $devs{$side} :
                              hostname_from_ip($side);

                    # 如果没有DNS则默认为IP
                    $dns = defined $dns ? $dns : "($side)";

                    $G->add_vertex($side);
                    debug "  make_graph() - add_vertex('$side')";

                    $GRAPH{$side}->{dns} = $dns;
                    $GRAPH{$side}->{isdev} = $is_dev;
                    $GRAPH{$side}->{seen}++;
                    $GRAPH{$side}->{location} = $locs{$side};
                }
            }

            # 添加边
            $G->add_edge($link,$dest);
            debug "  make_graph - add_edge('$link','$dest')";
        }
    }

    return $G;
}

# 获取主目录路径
# 处理图形文件路径
sub _homepath {
    my ($path, $default) = @_;

    my $home = $ENV{NETDISCO_HOME};
    my $item = setting('graph')->{$path} || $default;
    return undef unless defined($item);

    if ($item =~ m,^/,) {
        return $item;
    }
    else {
        $home =~ s,/*$,,;
        return $home . "/" . $item;
    }
}

1;
