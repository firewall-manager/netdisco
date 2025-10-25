package App::Netdisco::Worker::Plugin::DumpInfoCache;

# 信息缓存转储工作器插件
# 提供SNMP信息缓存转储功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Module::Load ();
use Data::Dumper;
use Storable 'dclone';

use App::Netdisco::Transport::SNMP;

# 注册检查阶段工作器
# 验证信息缓存转储操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $port, $extra) = map { $job->$_ } qw/device port extra/;

    # 加载必要的模块
    Module::Load::load 'Module::Info';
    Module::Load::load 'Data::Tie::Watch';

    # 检查设备参数
    return Status->error('Missing device (-d).')                 unless $device;
    return Status->error(sprintf "unknown device: %s.", $device) unless $device->in_storage;

    return Status->done('Dump info cache is able to run');
  }
);

# 注册主阶段工作器
# 转储SNMP信息缓存
register_worker(
  {phase => 'main', driver => 'snmp'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $class, $dumpclass) = map { $job->$_ } qw/device port extra/;

    # 设置SNMP类名
    $class = 'SNMP::Info::' . $class if $class and $class !~ m/^SNMP::Info::/;
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device, $class);

    # 设置转储类名
    $dumpclass = 'SNMP::Info::' . $dumpclass if $dumpclass and $dumpclass !~ m/^SNMP::Info::/;
    $dumpclass ||= ($snmp->class || $device->snmp_class);

    # 获取类的方法列表
    debug sprintf 'inspecting class %s', $dumpclass;
    my %sh   = Module::Info->new_from_loaded($dumpclass)->subroutines;
    my @subs = grep { $_ !~ m/^_/ } map { $_ =~ s/^.+:://; $_ }          ## no critic
      keys %sh;

    # 创建缓存和获取回调
    my $cache = {};
    my $fetch = sub {
      my ($self, $key) = @_;
      my $val = $self->Fetch($key);

      # 忽略特定方法
      my @ignore = qw(munge globals funcs Offline store sess debug snmp_ver);
      return $val if scalar grep { $_ eq $key } @ignore;

      # 处理存储的缓存数据
      (my $stripped = $key) =~ s/^_//;
      if (exists $snmp->{store}->{$stripped}) {
        $cache->{$key} = 1;
        $cache->{store}->{$stripped} = dclone $snmp->{store}->{$stripped};
      }
      return $val if exists $snmp->{store}->{$stripped};

      # 缓存获取的值
      $cache->{$key} = $val;
      return $val;
    };

    # 设置数据监视器
    my $watch = Data::Tie::Watch->new(-variable => $snmp, -fetch => [$fetch],);

    # 调用所有方法以触发缓存
    $snmp->$_ for @subs;
    $watch->Unwatch;

    # 输出缓存数据
    print Dumper($cache);
    return Status->done(sprintf "Dumped %s cache for %s", $dumpclass, $device->ip);
  }
);

true;
