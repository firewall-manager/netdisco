# Netdisco设备实体发现插件
# 此模块提供设备实体发现功能，用于通过SNMP发现和存储网络设备的机箱模块信息
package App::Netdisco::Worker::Plugin::Discover::Entities;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC 'schema';
use String::Util 'trim';
use Encode;

# 清理设备模块的辅助函数
my $clean = sub {
  my $device = shift;

  # 删除现有模块
  my $gone = $device->modules->delete;
  debug sprintf ' [%s] modules - removed %d chassis modules', $device->ip, $gone;

  # 创建伪机箱模块
  $device->modules->update_or_create({
    ip     => $device->ip,
    index  => 1,
    parent => 0,
    name   => 'chassis',
    class  => 'chassis',
    pos    => -1,

    # 描述信息过于冗长且链接无效
    # description => $device->description,
    sw_ver        => $device->os_ver,      # 软件版本
    serial        => $device->serial,      # 序列号
    model         => $device->model,       # 型号
    fru           => \'false',             # 非现场可更换单元
    last_discover => \'LOCALTIMESTAMP',    # 最后发现时间
  });
};

# 注册主阶段工作器 - 发现设备实体
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储

    # 如果跳过模块或禁用模块存储
    if (acl_matches($device, 'skip_modules') or not setting('store_modules')) {
      schema('netdisco')->txn_do($clean, $device);
      return Status->info(sprintf ' [%s] modules - store_modules is disabled (added one pseudo for chassis)',
        $device->ip);
    }

    # 建立SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");
    my $e_index = $snmp->e_index;         # 获取实体索引

    # 如果没有实体索引，创建伪机箱模块
    if (!defined $e_index) {
      schema('netdisco')->txn_do($clean, $device);
      return Status->info(sprintf ' [%s] modules - 0 chassis components (added one pseudo for chassis)', $device->ip);
    }

    # 获取实体MIB信息
    my $e_descr  = $snmp->e_descr;        # 实体描述
    my $e_type   = $snmp->e_type;         # 实体类型
    my $e_parent = $snmp->e_parent;       # 父实体
    my $e_name   = $snmp->e_name;         # 实体名称
    my $e_class  = $snmp->e_class;        # 实体类别
    my $e_pos    = $snmp->e_pos;          # 实体位置
    my $e_hwver  = $snmp->e_hwver;        # 硬件版本
    my $e_fwver  = $snmp->e_fwver;        # 固件版本
    my $e_swver  = $snmp->e_swver;        # 软件版本
    my $e_model  = $snmp->e_model;        # 实体型号
    my $e_serial = $snmp->e_serial;       # 实体序列号
    my $e_fru    = $snmp->e_fru;          # 现场可更换单元

    # 构建设备模块列表用于DBIC
    my (@modules, %seen_idx);
    foreach my $entry (keys %$e_index) {
      next unless defined $e_index->{$entry};
      next if $seen_idx{$e_index->{$entry}}++;    # 跳过重复索引

      # 验证索引是否为整数
      if ($e_index->{$entry} !~ m/^[0-9]+$/) {
        debug sprintf ' [%s] modules - index %s is not an integer', $device->ip, $e_index->{$entry};
        next;
      }

      # 构建模块记录
      push @modules, {
        index         => $e_index->{$entry},                                    # 索引
        type          => $e_type->{$entry},                                     # 类型
        parent        => $e_parent->{$entry},                                   # 父实体
        name          => trim(Encode::decode('UTF-8', $e_name->{$entry})),      # 名称
        class         => $e_class->{$entry},                                    # 类别
        pos           => $e_pos->{$entry},                                      # 位置
        hw_ver        => trim(Encode::decode('UTF-8', $e_hwver->{$entry})),     # 硬件版本
        fw_ver        => trim(Encode::decode('UTF-8', $e_fwver->{$entry})),     # 固件版本
        sw_ver        => trim(Encode::decode('UTF-8', $e_swver->{$entry})),     # 软件版本
        model         => trim(Encode::decode('UTF-8', $e_model->{$entry})),     # 型号
        serial        => trim(Encode::decode('UTF-8', $e_serial->{$entry})),    # 序列号
        fru           => $e_fru->{$entry},                                      # 现场可更换单元
        description   => trim(Encode::decode('UTF-8', $e_descr->{$entry})),     # 描述
        last_discover => \'LOCALTIMESTAMP',                                     # 最后发现时间
      };
    }

    # 处理无效父实体的实体
    foreach my $m (@modules) {
      if ($m->{parent} and not exists $seen_idx{$m->{parent}}) {

        # 某些组合设备如带FEX的Nexus或带卫星的ASR可能返回无效的EntityMIB树
        # 此变通方法将具有无效父实体的实体重新定位到树的根部，使其至少在模块标签页中可见

        debug sprintf ' [%s] Entity %s (%s) has invalid parent %s - attaching as root entity instead', $device->ip,
          ($m->{index} || '"unknown index"'), ($m->{name} || '"unknown name"'), $m->{parent};
        $m->{parent} = undef;    # 设置为根实体
      }
    }

    # 存储模块信息到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->modules->delete;      # 删除现有模块
      debug sprintf ' [%s] modules - removed %d chassis modules', $device->ip, $gone;
      $device->modules->populate(\@modules);    # 插入新模块

      return Status->info(sprintf ' [%s] modules - added %d new chassis modules', $device->ip, scalar @modules);
    });
  }
);

true;
