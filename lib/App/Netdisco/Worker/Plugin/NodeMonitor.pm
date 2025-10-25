package App::Netdisco::Worker::Plugin::NodeMonitor;

# 节点监控工作器插件
# 提供节点监控数据生成功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::NodeMonitor ();

# 注册主阶段工作器
# 生成节点监控数据
register_worker({ phase => 'main' }, sub {
  # 调用节点监控工具
  App::Netdisco::Util::NodeMonitor::monitor();
  return Status->done('Generated monitor data');
});

true;
