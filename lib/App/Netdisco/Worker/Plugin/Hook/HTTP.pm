# Netdisco HTTP钩子插件
# 此模块提供HTTP钩子功能，用于在特定事件发生时发送HTTP请求
package App::Netdisco::Worker::Plugin::Hook::HTTP;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Encode 'encode';
use MIME::Base64 'decode_base64';
use HTTP::Tiny;
use Template;

# 注册主阶段工作器 - 发送HTTP请求钩子
register_worker(
  {phase => 'main'},  # 主阶段工作器
  sub {
    my ($job, $workerconf) = @_;
    my $extra = from_json(decode_base64($job->extra || ''));  # 解码作业额外数据
    $job->subaction('');  # 清空子动作

    my $event_data  = $extra->{'event_data'};   # 事件数据
    my $action_conf = $extra->{'action_conf'};  # 动作配置
    $action_conf->{'body'} ||= to_json($event_data);  # 默认请求体为事件数据的JSON

    # 检查URL参数
    return Status->error('missing url parameter to http Hook') if !defined $action_conf->{'url'};

    # 初始化模板引擎和HTTP客户端
    my $tt   = Template->new({ENCODING => 'utf8'});
    my $http = HTTP::Tiny->new(timeout => (($action_conf->{'timeout'} || 5000) / 1000));  # 超时时间，默认5秒

    # 设置自定义请求头
    $action_conf->{'custom_headers'} ||= {};
    $action_conf->{'custom_headers'}->{'Content-Type'} ||= 'application/json; charset=UTF-8';  # 默认内容类型
    $action_conf->{'custom_headers'}->{'Authorization'} = ('Bearer ' . $action_conf->{'bearer_token'})  # Bearer令牌认证
      if $action_conf->{'bearer_token'};

    # 处理URL模板
    my ($orig_url, $url) = ($action_conf->{'url'}, undef);
    $action_conf->{'url_is_template'} ||= 1      if !exists $action_conf->{'url_is_template'};  # 默认为模板
    $tt->process(\$orig_url, $event_data, \$url) if $action_conf->{'url_is_template'};  # 处理URL模板
    $url ||= $orig_url;  # 使用原始URL作为后备

    # 处理请求体模板
    my ($orig_body, $body) = ($action_conf->{'body'}, undef);
    $action_conf->{'body_is_template'} ||= 1       if !exists $action_conf->{'body_is_template'};  # 默认为模板
    $tt->process(\$orig_body, $event_data, \$body) if $action_conf->{'body_is_template'};  # 处理请求体模板
    $body ||= $orig_body;  # 使用原始请求体作为后备

    # 发送HTTP请求
    my $response = $http->request(
      ($action_conf->{'method'} || 'POST'),  # HTTP方法，默认POST
      $url, {headers => $action_conf->{'custom_headers'}, content => encode('UTF-8', $body)},  # 请求参数
    );

    # 根据响应结果返回状态
    if ($action_conf->{'ignore_failure'} or $response->{'success'}) {  # 忽略失败或成功
      return Status->done(sprintf 'HTTP Hook: %s %s', $response->{'status'}, $response->{'reason'});
    }
    else {  # 失败
      return Status->error(sprintf 'HTTP Hook: %s %s (%s)',
        $response->{'status'}, $response->{'reason'}, ($response->{'content'} || 'no content'));
    }
  }
);

true;
