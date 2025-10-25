package App::Netdisco::DB::Result::Virtual::WalkJobs;

# 遍历任务虚拟结果类
# 提供需要执行遍历任务的设备虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('walk_jobs');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：遍历任务
# 查找需要执行遍历任务的设备，考虑设备跳过和延迟机制
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
    SELECT ip
    FROM device

    LEFT OUTER JOIN admin ON (device.ip = admin.device
                              AND admin.status = 'queued'
                              AND admin.backend IS NULL
                              AND admin.action = ?)

    FULL OUTER JOIN device_skip ON (device_skip.device = device.ip
                                    AND (device_skip.actionset @> string_to_array(?, '')
                                         OR (device_skip.deferrals >= ?
                                             AND device_skip.last_defer > (LOCALTIMESTAMP - ? ::interval))))

    WHERE admin.device IS NULL
      AND device.ip IS NOT NULL
      AND (device.vendor IS NULL OR device.vendor != 'netdisco')

    GROUP BY device.ip
    HAVING count(device_skip.backend) < (SELECT count(distinct(backend)) FROM device_skip)

    ORDER BY device.ip ASC
ENDSQL
);

# 定义虚拟视图的列
# 包含需要执行遍历任务的设备IP地址
__PACKAGE__->add_columns("ip", {data_type => "inet", is_nullable => 0},);

# 设置主键
__PACKAGE__->set_primary_key("ip");

1;
