package App::Netdisco::Worker::Plugin::Renumber;

# 设备重编号工作器插件
# 提供网络设备IP地址重编号功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use NetAddr::IP                 qw/:rfc3021 :lower/;
use App::Netdisco::Util::Device qw/get_device renumber_device/;

# 注册检查阶段工作器
# 验证设备重编号操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $port, $extra) = map { $job->$_ } qw/device port extra/;

    # 检查设备参数
    return Status->error('Missing device (-d).') unless defined $device;

    # 检查设备是否已发现
    if (!$device->in_storage) {
      return Status->error(sprintf "unknown device: %s.", $device);
    }

    # 解析新IP地址
    my $new_ip = NetAddr::IP->new($extra);
    unless ($new_ip and $new_ip->addr ne '0.0.0.0') {
      return Status->error("bad host or IP: " . ($extra || '0.0.0.0'));
    }

    debug sprintf 'renumber - from IP: %s', $device;
    debug sprintf 'renumber -   to IP: %s (param: %s)', $new_ip->addr, $extra;

    # 检查新旧IP是否相同
    if ($new_ip->addr eq $device->ip) {
      return Status->error('old and new are the same IP.');
    }

    # 检查新IP是否已被其他设备使用
    my $new_dev = get_device($new_ip->addr);
    if ($new_dev and $new_dev->in_storage and ($new_dev->ip ne $device->ip)) {
      return Status->error(sprintf "already know new device as: %s.", $new_dev->ip);
    }

    return Status->done('Renumber is able to run');
  }
);

# 注册主阶段工作器
# 执行设备重编号操作
register_worker(
  {phase => 'main'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $port, $extra) = map { $job->$_ } qw/device port extra/;

    # 获取旧IP地址并解析新IP地址
    my $old_ip = $device->ip;
    my $new_ip = NetAddr::IP->new($extra);

    # 执行设备重编号
    renumber_device($old_ip, $new_ip);
    return Status->done(sprintf 'Renumbered device %s to %s (%s).', $old_ip, $new_ip, ($device->dns || ''));
  }
);

true;
