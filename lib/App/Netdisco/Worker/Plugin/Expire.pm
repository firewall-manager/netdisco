package App::Netdisco::Worker::Plugin::Expire;

# 数据过期工作器插件
# 提供设备和节点数据过期清理功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Dancer::Plugin::DBIC 'schema';
use App::Netdisco::JobQueue 'jq_insert';
use App::Netdisco::Util::Statistics 'update_stats';
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::DB::ExplicitLocking ':modes';
use App::Netdisco::Util::Permission 'acl_matches_only';

# 注册主阶段工作器
# 执行数据过期清理操作
register_worker(
  {phase => 'main'},
  sub {
    my ($job, $workerconf) = @_;

    # 处理设备过期配置
    if (setting('expire_devices') and ref {} eq ref setting('expire_devices')) {
      foreach my $acl (keys %{setting('expire_devices')}) {
        my $days = setting('expire_devices')->{$acl};

        # 在数据库事务中处理设备过期
        schema('netdisco')->txn_do(sub {

          # 查找过期的设备
          my @hostlist
            = schema('netdisco')
            ->resultset('Device')
            ->search({
            -not_bool => 'is_pseudo', last_discover => \[q/< (LOCALTIMESTAMP - ?::interval)/, ($days * 86400)],
            })
            ->get_column('ip')
            ->all;

          # 处理每个过期设备
          foreach my $ip (@hostlist) {
            next unless acl_matches_only($ip, $acl);

            # 插入删除任务到作业队列
            jq_insert([{
              device => $ip, action => 'delete',
            }]);

            # 记录用户日志
            schema('netdisco')->resultset('UserLog')->create({
              username => ($ENV{USER}                      || 'scheduled'),
              userip   => ipv4_from_hostname($job->backend || setting('workers')->{'BACKEND'}),
              event    => 'expire_devices',
              details  => $ip,
            });
          }
        });
      }
    }

    # 处理节点过期配置
    if (setting('expire_nodes') and setting('expire_nodes') > 0) {
      schema('netdisco')->txn_do(sub {

        # 设置节点IP新鲜度
        my $freshness = (
          (defined setting('expire_nodeip_freshness')) ? setting('expire_nodeip_freshness') : setting('expire_nodes'));
        if ($freshness) {

          # 删除过期的节点IP记录
          schema('netdisco')
            ->resultset('NodeIp')
            ->search({time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, ($freshness * 86400)],})
            ->delete();
        }

        # 删除过期的节点记录
        schema('netdisco')
          ->resultset('Node')
          ->search({time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, (setting('expire_nodes') * 86400)],})
          ->delete();
      });
    }

    # 处理节点归档过期配置
    if (setting('expire_nodes_archive') and setting('expire_nodes_archive') > 0) {
      schema('netdisco')->txn_do(sub {

        # 设置节点IP新鲜度
        my $freshness
          = ((defined setting('expire_nodeip_freshness'))
          ? setting('expire_nodeip_freshness')
          : setting('expire_nodes_archive'));
        if ($freshness) {

          # 删除过期的节点IP记录
          schema('netdisco')
            ->resultset('NodeIp')
            ->search({time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, ($freshness * 86400)],})
            ->delete();
        }

        # 删除非活跃的过期节点记录
        schema('netdisco')->resultset('Node')->search({
          -not_bool => 'active',
          time_last => \[q/< (LOCALTIMESTAMP - ?::interval)/, (setting('expire_nodes_archive') * 86400)],
        })->delete();
      });
    }

    # 清理没有对应节点的node_ip记录
    schema('netdisco')->resultset('NodeIp')->search({
      mac => {
        -in => schema('netdisco')
          ->resultset('NodeIp')
          ->search({port => undef}, {join => 'nodes', select => [{distinct => 'me.mac'}],})
          ->as_query
      },
    })->delete;

    # 处理作业过期配置
    if (setting('expire_jobs') and setting('expire_jobs') > 0) {
      schema('netdisco')->txn_do_locked(
        'admin',
        EXCLUSIVE,
        sub {
          # 删除过期的管理作业记录
          schema('netdisco')
            ->resultset('Admin')
            ->search({entered => \[q/< (LOCALTIMESTAMP - ?::interval)/, (setting('expire_jobs') * 86400)],})
            ->delete();
        }
      );
    }

    # 处理用户日志过期配置
    if (setting('expire_userlog') and setting('expire_userlog') > 0) {
      schema('netdisco')->txn_do_locked(
        'admin',
        EXCLUSIVE,
        sub {
          # 删除过期的用户日志记录
          schema('netdisco')
            ->resultset('UserLog')
            ->search({creation => \[q/< (LOCALTIMESTAMP - ?::interval)/, (setting('expire_userlog') * 86400)],})
            ->delete();
        }
      );
    }

    # 更新统计信息
    update_stats();

    return Status->done('Checked expiry and updated stats');
  }
);

true;
