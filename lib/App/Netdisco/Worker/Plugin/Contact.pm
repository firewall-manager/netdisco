package App::Netdisco::Worker::Plugin::Contact;

# 联系人信息工作器插件
# 提供设备联系人信息更新功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;

# 注册检查阶段工作器
# 验证联系人信息更新操作的可行性
register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless defined shift->device;
  return Status->done('Contact is able to run');
});

# 注册主阶段工作器
# 更新设备联系人信息
register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $data) = map {$job->$_} qw/device extra/;

  # 直接更新伪设备数据库
  unless ($device->is_pseudo()) {
    # 使用读写社区字符串进行SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
      or return Status->defer("failed to connect to $device to update contact");

    my $rv = $snmp->set_contact($data);

    if (!defined $rv) {
      return Status->error(
        "failed to set contact on $device: ". ($snmp->error || ''));
    }

    # 确认设置成功
    $snmp->clear_cache;
    my $new_data = ($snmp->contact || '');
    if ($new_data ne $data) {
      return Status->error("verify of contact failed on $device: $new_data");
    }
  }

  # 更新Netdisco数据库
  $device->update({contact => $data});

  return Status->done("Updated contact on $device to [$data]");
});

true;
