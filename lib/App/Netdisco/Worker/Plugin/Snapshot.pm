package App::Netdisco::Worker::Plugin::Snapshot;

# SNMP快照工作器插件
# 提供SNMP快照收集和存储功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Snapshot 'make_snmpwalk_browsable';
use App::Netdisco::Transport::SNMP;
use MIME::Base64 'encode_base64';

# 注册检查阶段工作器
# 验证SNMP快照操作的可行性
register_worker({ phase => 'check' }, sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 检查设备参数
    return Status->error('Missing device (-d).')
      unless defined $device;

    # 检查设备是否已发现
    return Status->error(sprintf 'Unknown device: %s', ($device || ''))
      unless $device and $device->in_storage;

    return Status->done('Bulkwalk is able to run');
});

# 注册主阶段工作器
# 执行SNMP快照收集操作
register_worker({ phase => 'main', driver => 'snmp' }, sub {
    my ($job, $workerconf) = @_;
    my ($device, $extra) = map {$job->$_} qw/device extra/;

    # 设置SNMP选项
    set(net_snmp_options => {
      %{ setting('net_snmp_options') },
      'UseLongNames' => 1,	   # 返回完整OID标签
      'UseSprintValue' => 0,
      'UseEnums'	=> 0,	   # 不使用枚举值
      'UseNumeric' => 1,	   # 返回点分十进制OID
    });

    # 建立SNMP连接和会话
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device);
    my $sess = $snmp->session();
    my $from = SNMP::Varbind->new([ $extra || '.1' ]);

    # 初始化变量
    my $vars = [];
    my $errornum = 0;
    my %store = ();

    # 执行SNMP批量遍历
    debug sprintf 'bulkwalking %s from %s', $device->ip, ($extra || '.1');
    ($vars) = $sess->bulkwalk( 0, $snmp->{BulkRepeaters}, $from );

    # 检查SNMP错误
    if ( $sess->{ErrorNum} ) {
        return Status->error(
            sprintf 'snmp fatal error - %s', $sess->{ErrorStr});
    }

    # 处理SNMP遍历结果
    while (not $errornum) {
        my $var = shift @$vars or last;
        my $idx = $var->[0];
        $idx .= '.'. $var->[1] if $var->[1]; # 忽略.0
        my $val = $var->[2];

        # 检查是否为最后一个元素，V2设备可能报告ENDOFMIBVIEW即使实例或对象不存在
        last if $val eq 'ENDOFMIBVIEW';

        # 检查SNMP错误状态
        if ($val eq 'NOSUCHOBJECT') {
            return Status->error('snmp fatal error - NOSUCHOBJECT');
        }
        if ( $val eq 'NOSUCHINSTANCE' ) {
            return Status->error('snmp fatal error - NOSUCHINSTANCE');
        }

        # 检查是否已经看到过这个IID（循环检测）
        if (defined $store{$idx} and $store{$idx}) {
            return Status->error(sprintf 'snmp fatal error - looping at %s', $idx);
        }

        # 存储OID数据
        $store{$idx} = {
          oid       => $idx,
          oid_parts => [], # 故意的，通过make_snmpwalk_browsable()扩展
          value     => to_json([encode_base64($val, '')]),
        };
    }
    debug sprintf 'walked %d rows', scalar keys %store;

    # 在数据库事务中更新OID数据
    schema('netdisco')->txn_do(sub {
      my $gone = $device->oids->delete;
      debug sprintf 'removed %d old oids', $gone;
      $device->oids->populate([values %store]);
    });

    # loadmibs对于获取快照是可选的
    if (schema('netdisco')->resultset('SNMPObject')->count) {
        debug 'you have run loadmibs. promoting oids to browser data...';
        make_snmpwalk_browsable($device);
    }

    return Status->done(
      sprintf 'completed bulkwalk of %s entries from %s for %s', (scalar keys %store), ($extra || '.1'), $device->ip);
});

true;
