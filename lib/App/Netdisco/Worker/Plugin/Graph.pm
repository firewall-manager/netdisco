package App::Netdisco::Worker::Plugin::Graph;

# 网络图生成工作器插件
# 提供网络拓扑图数据生成功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Graph ();

# 注册主阶段工作器
# 生成网络拓扑图数据
register_worker({ phase => 'main' }, sub {
  # 调用图生成工具
  App::Netdisco::Util::Graph::graph();
  return Status->done('Generated graph data');
});

true;
