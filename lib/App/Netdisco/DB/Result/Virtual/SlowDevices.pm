package App::Netdisco::DB::Result::Virtual::SlowDevices;

# 慢设备虚拟结果类
# 提供执行缓慢的设备任务统计信息虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('slow_devices');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：慢设备统计
# 统计执行时间最长的设备任务，按执行时间降序排列
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
  SELECT a.action, a.device, a.started, a.finished,
      justify_interval(extract(epoch FROM (a.finished - a.started)) * interval '1 second') AS elapsed
    FROM admin a
    INNER JOIN (
      SELECT device, action, max(started) AS started
      FROM admin
      WHERE status = 'done'
        AND action IN ('discover','macsuck','arpnip')
      GROUP BY action, device
    ) b
    ON a.device = b.device AND a.started = b.started
    ORDER BY elapsed desc, action, device
    LIMIT 20
ENDSQL
);

# 定义虚拟视图的列
# 包含任务动作、设备、时间信息和执行时间
__PACKAGE__->add_columns(
  "action",  {data_type => "text",      is_nullable => 1}, "device",   {data_type => "inet",      is_nullable => 1},
  "started", {data_type => "timestamp", is_nullable => 1}, "finished", {data_type => "timestamp", is_nullable => 1},
  "elapsed", {data_type => "interval",  is_nullable => 1},
);

1;
