package App::Netdisco::Worker::Plugin::AddPseudoDevice;

# 添加伪设备工作器插件
# 提供添加伪设备到Netdisco数据库的功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::Statistics 'pretty_version';
use NetAddr::IP::Lite ':lower';

# 注册检查阶段工作器
# 验证添加伪设备的参数
register_worker({ phase => 'check' }, sub {
    my ($job, $workerconf) = @_;
    my $name  = $job->extra;
    my $ports = $job->port;

    # 检查设备IP参数
    return Status->error('Missing or invalid device IP (-d).')
      unless $job->device;
    my $devip = $job->device->ip;

    # 检查设备名称参数
    return Status->error('Missing or invalid device name (-e).')
      unless $name
      and $name =~ m/^[[:print:]]+$/
      and $name !~ m/[[:space:]]/;

    # 验证IP地址有效性
    my $ip = NetAddr::IP::Lite->new($devip);
    return Status->error('Missing or invalid device IP (-d).')
      unless ($ip and $ip->addr ne '0.0.0.0');

    # 检查端口数量参数
    return Status->error('Missing or invalid number of device ports (-p).')
      unless $ports
      and $ports =~ m/^[[:digit:]]+$/;

    return Status->done('Pseudo Devive can be added');
});

# 注册主阶段工作器
# 创建伪设备并添加到数据库
register_worker({ phase => 'main' }, sub {
    my ($job, $workerconf) = @_;
    my $devip = $job->device->ip;
    my $name  = $job->extra;
    my $ports = $job->port;

    # 在数据库事务中创建伪设备
    schema('netdisco')->txn_do(sub {
      my $device = schema('netdisco')->resultset('Device')
        ->create({
          ip => $devip,
          dns => (hostname_from_ip($devip) || ''),
          name => $name,
          vendor => 'netdisco',
          model => 'pseudodevice',
          num_ports => $ports,
          os => 'netdisco',
          os_ver => pretty_version($App::Netdisco::VERSION, 3),
          layers => '00000100',
          last_discover => \'LOCALTIMESTAMP',
          is_pseudo => \'true',
        });
      return unless $device;

      # 创建设备端口
      $device->ports->populate([
        [qw/port type descr/],
        map {["Port$_", 'other', "Port$_"]} @{[1 .. $ports]},
      ]);

      # device_ip表用于显示拓扑是否"损坏"
      schema('netdisco')->resultset('DeviceIp')
        ->create({
          ip => $devip,
          alias => $devip,
        });
    });

    return Status->done(
      sprintf "Pseudo Devive %s (%s) added", $devip, $name);
});

true;
