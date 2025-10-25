# Netdisco执行钩子插件
# 此模块提供执行钩子功能，用于在特定事件发生时执行外部命令
package App::Netdisco::Worker::Plugin::Hook::Exec;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use MIME::Base64 'decode_base64';
use Command::Runner;
use Template;

# 注册主阶段工作器 - 执行外部命令钩子
register_worker(
  {phase => 'main'},    # 主阶段工作器
  sub {
    my ($job, $workerconf) = @_;
    my $extra = from_json(decode_base64($job->extra || ''));    # 解码作业额外数据

    # 构建事件数据
    my $event_data  = {('ndo' => $ENV{NETDISCO_DO}), %{$extra->{'event_data'} || {}}};    # 事件数据
    my $action_conf = $extra->{'action_conf'};                                            # 动作配置

    # 检查命令参数
    return Status->error('missing cmd parameter to exec Hook') if !defined $action_conf->{'cmd'};

    # 初始化模板引擎
    my $tt = Template->new({ENCODING => 'utf8'});
    my ($orig_cmd, $cmd) = ($action_conf->{'cmd'}, undef);                                   # 原始命令和处理后的命令
    $action_conf->{'cmd_is_template'} ||= 1 if !exists $action_conf->{'cmd_is_template'};    # 默认为模板

    # 处理模板命令
    if ($action_conf->{'cmd_is_template'}) {
      if (ref $orig_cmd) {                                                                   # 命令是数组
        foreach my $part (@$orig_cmd) {
          my $tmp_part = undef;
          $tt->process(\$part, $event_data, \$tmp_part);                                     # 处理模板
          push @$cmd, $tmp_part;
        }
      }
      else {                                                                                 # 命令是字符串
        $tt->process(\$orig_cmd, $event_data, \$cmd);                                        # 处理模板
      }
    }
    $cmd ||= $orig_cmd;                                                                      # 使用原始命令作为后备

    # 执行命令
    my $result = Command::Runner->new(
      command => $cmd,                                                                                 # 命令
      timeout => ($action_conf->{'timeout'} || 60),                                                    # 超时时间，默认60秒
      env     => {%ENV, ND_EVENT => $action_conf->{'event'}, ND_DEVICE_IP => $event_data->{'ip'},},    # 环境变量
    )->run();

    $result->{cmd} = $cmd;                                                                             # 保存执行的命令
    $job->subaction(to_json($result));                                                                 # 设置子动作结果

    # 根据结果返回状态
    if ($action_conf->{'ignore_failure'} or not $result->{'result'}) {                                 # 忽略失败或成功
      return Status->done(sprintf 'Exec Hook: exit status %s', $result->{'result'});
    }
    else {                                                                                             # 失败
      return Status->error(sprintf 'Exec Hook: exit status %s', $result->{'result'});
    }
  }
);

true;
