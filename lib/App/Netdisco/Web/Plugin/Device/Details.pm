# Netdisco 设备详情管理插件
# 此模块提供设备详细信息的查看功能，包括设备属性、电源信息、接口和序列号等
package App::Netdisco::Web::Plugin::Device::Details;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

use List::MoreUtils 'singleton';

# 注册设备标签页 - 设备详情页面
register_device_tab({ tag => 'details', label => 'Details' });

# 设备详情表格数据路由 - 需要用户登录
ajax '/ajax/content/device/details' => require_login sub {
    # 获取查询参数中的设备标识
    my $q = param('q');
    # 根据设备标识查找设备，如果找不到则返回错误
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);

    # 获取设备详细信息，包括时间戳和自定义字段
    my @results
        = schema(vars->{'tenant'})->resultset('Device')
                                  ->search({ 'me.ip' => $device->ip })
                                  ->with_times
                                  ->with_custom_fields
                                  ->hri->all;

    # 获取设备电源信息，包括PoE统计
    my @power
        = schema(vars->{'tenant'})->resultset('DevicePower')
        ->search( { 'me.ip' => $device->ip } )->with_poestats->hri->all;

    # 获取设备接口信息
    my @interfaces = $device->device_ips->hri->all;

    # 获取机箱序列号信息
    my @serials = $device->modules->search({
        class => 'chassis',
        -and => [
          { serial => { '!=' => '' } },
          { serial => { '!=' => undef } },
        ],
    })->order_by('pos')->get_column('serial')->all;

    # 根据配置过滤隐藏的标签
    my @hide = @{ setting('hide_tags')->{'device'} };

    # 设置内容类型并渲染模板
    content_type('text/html');
    template 'ajax/device/details.tt', {
      d => $results[0], p => \@power,                    # 设备详情和电源信息
      interfaces => \@interfaces,                        # 接口信息
      has_snapshot =>                                    # 是否有快照数据
        $device->oids->search({-bool => \q{ jsonb_typeof(value) = 'array' }})->count,
      filtered_tags => [ singleton (@{ $device->tags || [] }, @hide, @hide) ],  # 过滤后的标签
      serials => [sort keys %{ { map {($_ => $_)} (@serials, ($device->serial ? $device->serial : ())) } }],  # 序列号列表
    }, { layout => undef };
};

1;
