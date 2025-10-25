package App::Netdisco::Worker::Plugin::Stats;

# 统计信息工作器插件
# 提供系统统计信息更新功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Statistics ();

# 注册主阶段工作器
# 更新系统统计信息
register_worker({ phase => 'main' }, sub {
  # 调用统计信息更新工具
  App::Netdisco::Util::Statistics::update_stats();
  return Status->done('Updated statistics');
});

true;
