# Netdisco 设备搜索插件
# 此模块提供设备搜索功能，支持多种搜索条件和API接口
package App::Netdisco::Web::Plugin::Search::Device;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use List::MoreUtils ();

use App::Netdisco::Web::Plugin;

# 注册搜索标签页 - 设备搜索，支持CSV导出和API接口
register_search_tab({
    tag => 'device',
    label => 'Device',
    provides_csv => 1,
    api_endpoint => 1,
    api_parameters => [
      q => {
        description => 'Partial match of Device contact, serial, chassis ID, module serials, location, name, description, dns, or any IP alias',
      },
      name => {
        description => 'Partial match of the Device name',
      },
      location => {
        description => 'Partial match of the Device location',
      },
      dns => {
        description => 'Partial match of any of the Device IP aliases',
      },
      ip => {
        description => 'IP or IP Prefix within which the Device must have an interface address',
      },
      description => {
        description => 'Partial match of the Device description',
      },
      mac => {
        description => 'MAC Address of the Device or any of its Interfaces',
      },
      model => {
        description => 'Exact match of the Device model',
      },
      os => {
        description => 'Exact match of the Device operating system',
      },
      os_ver => {
        description => 'Exact match of the Device operating system version',
      },
      vendor => {
        description => 'Exact match of the Device vendor',
      },
      layers => {
        description => 'OSI Layer which the device must support',
      },
      matchall => {
        description => 'If true, all fields (except "q") must match the Device',
        type => 'boolean',
        default => 'false',
      },
      seeallcolumns => {
        description => 'If true, all columns of the Device will be shown',
        type => 'boolean',
        default => 'false',
      },
    ],
});

# 设备搜索路由 - 支持各种属性或默认全匹配
get '/ajax/content/search/device' => require_login sub {
    # 检查是否有特定搜索选项
    my $has_opt = List::MoreUtils::any { param($_) }
      qw/name location dns ip description model os os_ver vendor layers mac/;
    my $rs;
    my $rs_columns;
    my $see_all = param('seeallcolumns');

    # 根据是否显示所有列选择结果集
    if ($see_all) {
      $rs_columns = schema(vars->{'tenant'})->resultset('Device');
    }
    else {
      # 只选择特定列以提高性能
      $rs_columns = schema(vars->{'tenant'})->resultset('Device')->columns(
            [   "ip",       "dns",   "name",
                "location", "model", "os_ver", "serial", "chassis_id"
            ]
        );
    }

    # 根据是否有特定选项选择搜索方法
    if ($has_opt) {
        # 使用字段搜索
        $rs = $rs_columns->with_times->search_by_field( scalar params );
    }
    else {
        # 使用模糊搜索
        my $q = param('q');
        send_error( 'Missing query', 400 ) unless $q;

        $rs = $rs_columns->with_times->search_fuzzy($q);
    }

    # 获取结果，必须在search_fuzzy之后调用with_module_serials
    my @results = $rs->with_module_serials
                     ->hri->all;
    return unless scalar @results;

    # 去重结果，因为在with_module_serials之后不再唯一
    my %seen = ();
    @results = grep { ! $seen{$_->{ip}}++ } @results;

    # 展平设备序列号、设备机箱ID和模块序列号，并去重
    map {$_->{module_serials} = [ List::MoreUtils::uniq
                                  sort
                                  grep {length}
                                  grep {defined} (
                                    $_->{serial},           # 设备序列号
                                    $_->{chassis_id},       # 机箱ID
                                    ( map { $_->{serial} }  # 模块序列号
                                          @{ $_->{module_serials} } )
                                  )
                                ]} @results;

    # 根据请求类型返回不同格式的数据
    if ( request->is_ajax ) {
        # AJAX请求：返回JSON格式的HTML模板
        my $json = to_json( \@results );
        template 'ajax/search/device.tt', { results => $json }, { layout => 'noop' };;
    }
    else {
        # 非AJAX请求：返回CSV格式数据
        header( 'Content-Type' => 'text/comma-separated-values' );
        template 'ajax/search/device_csv.tt', { results => \@results, }, { layout => 'noop' };
    }
};

1;
