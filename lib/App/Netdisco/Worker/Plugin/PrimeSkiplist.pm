package App::Netdisco::Worker::Plugin::PrimeSkiplist;

# 跳过列表初始化工作器插件
# 提供设备操作跳过列表初始化功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'get_denied_actions';
use App::Netdisco::Util::MCE 'parse_max_workers';
use App::Netdisco::Backend::Job;

use Try::Tiny;

# 注册主阶段工作器
# 初始化设备操作跳过列表
register_worker(
  {phase => 'main'},
  sub {
    my ($job, $workerconf) = @_;
    my $happy = false;

    # 获取设备和跳过列表结果集
    my $devices   = schema(vars->{'tenant'})->resultset('Device');
    my $rs        = schema(vars->{'tenant'})->resultset('DeviceSkip');
    my %actionset = ();

    # 遍历所有设备，获取被拒绝的操作
    while (my $d = $devices->next) {
      my @badactions = get_denied_actions($d);
      $actionset{$d->ip} = \@badactions if scalar @badactions;
    }

    debug sprintf 'priming device action skip list for %d devices', scalar keys %actionset;

    # 解析最大工作器数量
    my $max_workers = parse_max_workers(setting('workers')->{tasks}) || 0;

    # 在数据库事务中更新跳过列表
    try {
      schema(vars->{'tenant'})->txn_do(sub {
        $rs->update_or_create({backend => setting('workers')->{'BACKEND'}, device => $_, actionset => $actionset{$_},},
          {key => 'primary'})
          for keys %actionset;
      });

      # 添加一个虚拟记录，允许*walk操作看到有后端在运行
      $rs->update_or_create(
        {
          backend    => setting('workers')->{'BACKEND'},
          device     => '255.255.255.255',
          last_defer => \'LOCALTIMESTAMP',
          deferrals  => $max_workers,
        },
        {key => 'primary'}
      );

      $happy = true;
    }
    catch {
      error $_;
    };

    # 返回操作结果
    if ($happy) {
      return Status->done("Primed device action skip list");
    }
    else {
      return Status->error("Failed to prime device action skip list");
    }
  }
);

true;
