# Netdisco 端口VLAN不匹配报告插件
# 此模块提供端口VLAN不匹配的检测功能，用于识别网络中端口VLAN配置不一致的情况
package App::Netdisco::Web::Plugin::Report::PortVLANMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use List::MoreUtils qw/listcmp sort_by/;

# 注册报告 - 端口VLAN不匹配，支持CSV导出和API接口
register_report({
  category     => 'Port',               # 端口类别
  tag          => 'portvlanmismatch',
  label        => 'Mismatched VLANs',
  provides_csv => 1,                    # 支持CSV导出
  api_endpoint => 1,                    # 支持API接口
});

# 端口VLAN不匹配报告路由 - 检测端口VLAN配置不匹配的情况
get '/ajax/content/report/portvlanmismatch' => require_login sub {

  # 检查是否有设备数据
  return unless schema(vars->{'tenant'})->resultset('Device')->count;

  # 查询端口VLAN不匹配数据
  my @results = schema(vars->{'tenant'})->resultset('Virtual::PortVLANMismatch')->search(
    {},
    {
      # 绑定VLAN过滤参数：根据配置决定是否隐藏默认VLAN
      bind => [
        setting('sidebar_defaults')->{'device_ports'}->{'p_hide1002'}->{'default'}
        ? (1002, 1003, 1004, 1005)
        : (0, 0, 0, 0)
      ],
    }
  )->hri->all;

#    # 注意：生成的列表没有HTML转义，所以必须用grep进行清理
#    foreach my $res (@results) {
#        my @left  = grep {m/^(?:n:)?\d+$/} map {s/\s//g; $_} split ',', $res->{left_vlans};
#        my @right = grep {m/^(?:n:)?\d+$/} map {s/\s//g; $_} split ',', $res->{right_vlans};
#
#        my %new = (0 => [], 1 => []);
#        my %cmp = listcmp @left, @right;
#        foreach my $vlan (keys %cmp) {
#            map { push @{ $new{$_} }, ( (2 == scalar @{ $cmp{$vlan} }) ? $vlan : "<strong>$vlan</strong>" ) } @{ $cmp{$vlan} };
#        }
#
#        $res->{left_vlans}  = join ', ', sort_by { (my $a = $_) =~ s/\D//g; sprintf "%05d", $a } @{ $new{0} };
#        $res->{right_vlans} = join ', ', sort_by { (my $a = $_) =~ s/\D//g; sprintf "%05d", $a } @{ $new{1} };
#    }

  # 处理VLAN列表数据，将数组转换为逗号分隔的字符串
  foreach my $res (@results) {
    $res->{only_left_vlans}  = join ', ', @{$res->{only_left_vlans}  || []};    # 左侧独有VLAN
    $res->{only_right_vlans} = join ', ', @{$res->{only_right_vlans} || []};    # 右侧独有VLAN
  }

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/portvlanmismatch.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/portvlanmismatch_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
