# Netdisco 设备模块管理插件
# 此模块提供设备硬件模块的查看功能，包括模块排序和层次结构显示
package App::Netdisco::Web::Plugin::Device::Modules;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::Web (); # 用于模块排序功能
use App::Netdisco::Web::Plugin;

# 注册设备标签页 - 设备模块页面
register_device_tab({ tag => 'modules', label => 'Modules' });

# 设备模块数据路由 - 需要用户登录
ajax '/ajax/content/device/modules' => require_login sub {
    # 获取查询参数中的设备标识
    my $q = param('q');

    # 根据设备标识查找设备，如果找不到则返回错误
    my $device = schema(vars->{'tenant'})->resultset('Device')
      ->search_for_device($q) or send_error('Bad device', 400);
    
    # 获取设备的所有模块，按父级、类别、位置和索引排序
    my @set = $device->modules->search({}, {order_by => { -asc => [qw/parent class pos index/] }});

    # 对模块进行排序（空集合会显示"无记录"消息）
    my $results = &App::Netdisco::Util::Web::sort_modules( \@set );
    return unless scalar %$results;

    # 设置内容类型并渲染模块模板
    content_type('text/html');
    template 'ajax/device/modules.tt', {
      nodes => $results,  # 排序后的模块节点数据
    }, { layout => 'noop' };
};

true;
