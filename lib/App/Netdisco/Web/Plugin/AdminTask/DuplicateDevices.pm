# Netdisco 重复设备管理插件
# 此模块提供重复设备检测功能，用于识别具有相同序列号的设备
package App::Netdisco::Web::Plugin::AdminTask::DuplicateDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 重复设备检测
register_admin_task({
  tag => 'duplicatedevices',
  label => 'Duplicate Devices',
});

# 重复设备检测路由 - 查找具有相同序列号的设备
ajax '/ajax/content/admin/duplicatedevices' => require_role admin => sub {
    # 查询重复设备：查找序列号出现多次的设备
    my @set = schema(vars->{'tenant'})->resultset('Device')->search({
      serial => { '-in' => schema(vars->{'tenant'})->resultset('Device')->search({
          '-and' => [serial => { '!=', undef }, serial => { '!=', '' }],  # 序列号不为空
        }, {
          group_by => ['serial'],        # 按序列号分组
          having => \'count(*) > 1',     # 计数大于1（重复）
          columns => 'serial',           # 只选择序列号列
        })->as_query
      },
    }, { columns => [qw/ip dns contact location name model os_ver serial/] })  # 选择设备基本信息
      ->with_times->hri->all;  # 包含时间信息并返回哈希引用数组

    content_type('text/html');
    # 渲染重复设备模板
    template 'ajax/admintask/duplicatedevices.tt', {
      results => \@set
    }, { layout => undef };
};

true;
