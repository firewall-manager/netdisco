package App::Netdisco::DB::Result::Virtual::PollerPerformance;

# 轮询器性能虚拟结果类
# 提供轮询器性能统计信息的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table('poller_performance');
__PACKAGE__->result_source_instance->is_virtual(1);

# 虚拟视图定义：轮询器性能统计
# 统计轮询器任务的性能指标，包括执行时间和设备数量
__PACKAGE__->result_source_instance->view_definition(
  <<ENDSQL
  SELECT action,
         to_char( entered, 'YYYY-MM-DD HH24:MI:SS' ) AS entered_stamp,
         COUNT( device ) AS number,
         MIN( started ) AS start,
         MAX( finished ) AS end,
         justify_interval(
           extract ( epoch FROM( max( finished ) - min( started ) ) )
             * interval '1 second'
         ) AS elapsed
    FROM admin
    WHERE action IN ( 'discover', 'macsuck', 'arpnip', 'nbtstat' ) 
    GROUP BY action, to_char( entered, 'YYYY-MM-DD HH24:MI' ), entered
    HAVING count( device ) > 1
      AND SUM( CASE WHEN status = 'queued' THEN 1 ELSE 0 END ) = 0
    ORDER BY entered_stamp DESC, elapsed DESC
    LIMIT 30
ENDSQL
);

# 定义虚拟视图的列
# 包含轮询器任务的动作、时间戳、设备数量和执行时间
__PACKAGE__->add_columns(
  "action",        {data_type => "text",      is_nullable => 1},
  "entered_stamp", {data_type => "text",      is_nullable => 1},
  "number",        {data_type => "integer",   is_nullable => 1},
  "start",         {data_type => "timestamp", is_nullable => 1},
  "end",           {data_type => "timestamp", is_nullable => 1},
  "elapsed",       {data_type => "interval",  is_nullable => 1},
);

1;
