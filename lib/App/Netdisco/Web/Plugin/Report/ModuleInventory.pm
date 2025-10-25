# Netdisco 设备模块清单报告插件
# 此模块提供设备模块清单统计功能，用于分析网络中设备模块的分布和配置情况
package App::Netdisco::Web::Plugin::Report::ModuleInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;
use List::MoreUtils ();

# 注册报告 - 设备模块清单，支持CSV导出
register_report({
  category     => 'Device',             # 设备类别
  tag          => 'moduleinventory',
  label        => 'Module Inventory',
  provides_csv => 1,                    # 支持CSV导出
});

# 模板前钩子 - 处理搜索侧边栏模板的选中项
hook 'before_template' => sub {
  my $tokens = shift;

  # 只对模块清单相关路径生效
  return
    unless (request->path eq uri_for('/report/moduleinventory')->path
    or index(request->path, uri_for('/ajax/content/report/moduleinventory')->path) == 0);

  # 用于在搜索侧边栏模板中设置选中项
  foreach my $opt (qw/class/) {
    my $p = (
      ref [] eq ref param($opt)               # 检查参数是否为数组引用
      ? param($opt)
      : (param($opt) ? [param($opt)] : [])    # 转换为数组引用
    );
    $tokens->{"${opt}_lkp"} = {map { $_ => 1 } @$p};    # 创建查找哈希
  }
};

# 设备模块数据路由 - 提供DataTables格式的模块数据
get '/ajax/content/report/moduleinventory/data' => require_login sub {

  # 验证DataTables必需的draw参数
  send_error('Missing parameter', 400) unless (param('draw') && param('draw') =~ /\d+/);

  # 获取设备模块结果集
  my $rs = schema(vars->{'tenant'})->resultset('DeviceModule');

  # 如果指定了FRU（现场可更换单元）选项，只查询FRU模块
  $rs = $rs->search({-bool => 'fru'}) if param('fruonly');

  # 如果指定了设备参数，进行模糊搜索获取设备IP列表
  if (param('device')) {
    my @ips = schema(vars->{'tenant'})->resultset('Device')->search_fuzzy(param('device'))->get_column('ip')->all;

    params->{'ips'} = \@ips;    # 设置IP参数
  }

  # 按字段搜索并选择模块信息字段
  $rs = $rs->search_by_field(scalar params)->columns([
    'ip',     'description', 'name',   'class',     # 基本模块信息
    'type',   'serial',      'hw_ver', 'fw_ver',    # 模块类型和版本信息
    'sw_ver', 'model'                               # 软件版本和型号
  ])->search(
    {},
    {
      '+columns' => [qw/ device.dns device.name /],    # 添加设备DNS和名称
      join       => 'device',                          # 连接设备表
      collapse   => 1,                                 # 折叠重复记录
    }
  );

  # 展开参数（用于DataTables处理）
  my $exp_params = expand_hash(scalar params);

  # 获取总记录数
  my $recordsTotal = $rs->count;

  # 获取过滤后的数据
  my @data = $rs->get_datatables_data($exp_params)->hri->all;

  # 获取过滤后的记录数
  my $recordsFiltered = $rs->get_datatables_filtered_count($exp_params);

  content_type 'application/json';

  # 返回DataTables格式的JSON数据
  return to_json({
    draw            => int(param('draw')),       # DataTables请求标识
    recordsTotal    => int($recordsTotal),       # 总记录数
    recordsFiltered => int($recordsFiltered),    # 过滤后记录数
    data            => \@data,                   # 数据数组
  });
};

# 设备模块内容路由 - 显示设备模块清单信息
get '/ajax/content/report/moduleinventory' => require_login sub {

  # 检查是否有搜索选项参数
  my $has_opt = List::MoreUtils::any { param($_) }
  qw/device description name type model serial class/;

  # 获取设备模块结果集
  my $rs = schema(vars->{'tenant'})->resultset('DeviceModule');

  # 如果指定了FRU选项，只查询FRU模块
  $rs = $rs->search({-bool => 'fru'}) if param('fruonly');
  my @results;

  # 如果有搜索选项且不是AJAX请求，执行详细搜索
  if ($has_opt && !request->is_ajax) {

    # 如果指定了设备参数，进行模糊搜索获取设备IP列表
    if (param('device')) {
      my @ips = schema(vars->{'tenant'})->resultset('Device')->search_fuzzy(param('device'))->get_column('ip')->all;

      params->{'ips'} = \@ips;
    }

    # 按字段搜索并选择模块信息字段
    @results = $rs->search_by_field(scalar params)->columns([
      'ip',     'description', 'name',   'class',     # 基本模块信息
      'type',   'serial',      'hw_ver', 'fw_ver',    # 模块类型和版本信息
      'sw_ver', 'model'                               # 软件版本和型号
    ])->search(
      {},
      {
        '+columns' => [qw/ device.dns device.name /],    # 添加设备DNS和名称
        join       => 'device',                          # 连接设备表
        collapse   => 1,                                 # 折叠重复记录
      }
    )->hri->all;

    return unless scalar @results;                       # 如果没有结果则返回
  }

  # 如果没有搜索选项，显示模块类别统计
  elsif (!$has_opt) {

    # 查询模块类别统计
    @results = $rs->search(
      {class => {'!=', undef}},    # 类别不为空
      {
        select   => ['class', {count => 'class'}],    # 选择类别和计数
        as       => [qw/ class count /],              # 字段别名
        group_by => [qw/ class /]                     # 按类别分组
      }
    )->order_by({-desc => 'count'})->hri->all;        # 按计数降序排列

    return unless scalar @results;                    # 如果没有结果则返回
  }

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/moduleinventory.tt', {results => $json, opt => $has_opt}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/moduleinventory_csv.tt', {results => \@results, opt => $has_opt}, {layout => 'noop'};
  }
};

1;
