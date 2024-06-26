local utils = import 'mixin-utils/utils.libsonnet';

{
  // Helper function to produce failure rate in percentage queries for native and classic histograms.
  // Takes a metric name and a selector as strings and returns a dictionary with classic and native queries.
  nativeClassicFailureRate(metric, selector):: {
    local template = |||
      (
          # gRPC errors are not tracked as 5xx but "error".
          sum(%(countFailQuery)s)
          or
          # Handle the case no failure has been tracked yet.
          vector(0)
      )
      /
      sum(%(countQuery)s)
    |||,
    classic: template % {
      countFailQuery: utils.nativeClassicHistogramCountRate(metric, selector + ',status_code=~"5.*|error"').classic,
      countQuery: utils.nativeClassicHistogramCountRate(metric, selector).classic,
    },
    native: template % {
      countFailQuery: utils.nativeClassicHistogramCountRate(metric, selector + ',status_code=~"5.*|error"').native,
      countQuery: utils.nativeClassicHistogramCountRate(metric, selector).native,
    },
  },

  // This object contains common queries used in the Mimir dashboards.
  // These queries are NOT intended to be configurable or overriddeable via jsonnet,
  // but they're defined in a common place just to share them between different dashboards.
  queries:: {
    // Define the supported replacement variables in a single place. Most of them are frequently used.
    local variables = {
      gatewayMatcher: $.jobMatcher($._config.job_names.gateway),
      distributorMatcher: $.jobMatcher($._config.job_names.distributor),
      queryFrontendMatcher: $.jobMatcher($._config.job_names.query_frontend),
      rulerMatcher: $.jobMatcher($._config.job_names.ruler),
      alertmanagerMatcher: $.jobMatcher($._config.job_names.alertmanager),
      namespaceMatcher: $.namespaceMatcher(),
      writeHTTPRoutesRegex: $.queries.write_http_routes_regex,
      writeGRPCRoutesRegex: $.queries.write_grpc_routes_regex,
      readHTTPRoutesRegex: $.queries.read_http_routes_regex,
      perClusterLabel: $._config.per_cluster_label,
      recordingRulePrefix: $.recordingRulePrefix($.jobSelector('any')),  // The job name does not matter here.
      groupPrefixJobs: $._config.group_prefix_jobs,
    },

    write_http_routes_regex: 'api_(v1|prom)_push|otlp_v1_metrics',
    write_grpc_routes_regex: '/distributor.Distributor/Push|/httpgrpc.*',
    read_http_routes_regex: '(prometheus|api_prom)_api_v1_.+',
    query_http_routes_regex: '(prometheus|api_prom)_api_v1_query(_range)?',

    gateway: {
      // deprecated, will be removed
      writeRequestsPerSecond: 'cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(writeHTTPRoutesRegex)s"}' % variables,
      readRequestsPerSecond: 'cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(readHTTPRoutesRegex)s"}' % variables,

      local p = self,
      requestsPerSecondMetric: 'cortex_request_duration_seconds',
      writeRequestsPerSecondSelector: '%(gatewayMatcher)s, route=~"%(writeHTTPRoutesRegex)s"' % variables,
      readRequestsPerSecondSelector: '%(gatewayMatcher)s, route=~"%(readHTTPRoutesRegex)s"' % variables,

      // Write failures rate as percentage of total requests.
      writeFailuresRate: $.nativeClassicFailureRate(p.requestsPerSecondMetric, p.writeRequestsPerSecondSelector),

      // Read failures rate as percentage of total requests.
      readFailuresRate: $.nativeClassicFailureRate(p.requestsPerSecondMetric, p.readRequestsPerSecondSelector),
    },

    distributor: {
      // deprecated, will be removed
      writeRequestsPerSecond: 'cortex_request_duration_seconds_count{%(distributorMatcher)s, route=~"%(writeGRPCRoutesRegex)s|%(writeHTTPRoutesRegex)s"}' % variables,

      local p = self,
      requestsPerSecondMetric: 'cortex_request_duration_seconds',
      writeRequestsPerSecondSelector: '%(distributorMatcher)s, route=~"%(writeGRPCRoutesRegex)s|%(writeHTTPRoutesRegex)s"' % variables,
      samplesPerSecond: 'sum(%(groupPrefixJobs)s:cortex_distributor_received_samples:rate5m{%(distributorMatcher)s})' % variables,
      exemplarsPerSecond: 'sum(%(groupPrefixJobs)s:cortex_distributor_received_exemplars:rate5m{%(distributorMatcher)s})' % variables,

      // Write failures rate as percentage of total requests.
      writeFailuresRate: $.nativeClassicFailureRate(p.requestsPerSecondMetric, p.writeRequestsPerSecondSelector),
    },

    query_frontend: {
      // deprecated, will be removed
      readRequestsPerSecond: 'cortex_request_duration_seconds_count{%(queryFrontendMatcher)s, route=~"%(readHTTPRoutesRegex)s"}' % variables,

      local p = self,
      readRequestsPerSecondMetric: 'cortex_request_duration_seconds',
      readRequestsPerSecondSelector: '%(queryFrontendMatcher)s, route=~"%(readHTTPRoutesRegex)s"' % variables,
      // These query routes are used in the overview and other dashboard, everythign else is considered "other" queries.
      // Has to be a list to keep the same colors as before, see overridesNonErrorColorsPalette.
      local overviewRoutes = [
        { name: 'instantQuery', displayName: 'instant queries', route: '/api/v1/query', routeLabel: '_api_v1_query' },
        { name: 'rangeQuery', displayName: 'range queries', route: '/api/v1/query_range', routeLabel: '_api_v1_query_range' },
        { name: 'labelNames', displayName: '"label names" queries', route: '/api/v1/labels', routeLabel: '_api_v1_labels' },
        { name: 'labelValues', displayName: '"label values" queries', route: '/api/v1/label_name_values', routeLabel: '_api_v1_label_name_values' },
        { name: 'series', displayName: 'series queries', route: '/api/v1/series', routeLabel: '_api_v1_series' },
        { name: 'remoteRead', displayName: 'remote read queries', route: '/api/v1/read', routeLabel: '_api_v1_read' },
        { name: 'metadata', displayName: 'metadata queries', route: '/api/v1/metadata', routeLabel: '_api_v1_metadata' },
        { name: 'exemplars', displayName: 'exemplar queries', route: '/api/v1/query_exemplars', routeLabel: '_api_v1_query_exemplars' },
        { name: 'activeSeries', displayName: '"active series" queries', route: '/api/v1/cardinality_active_series', routeLabel: '_api_v1_cardinality_active_series' },
        { name: 'labelNamesCardinality', displayName: '"label name cardinality" queries', route: '/api/v1/cardinality_label_names', routeLabel: '_api_v1_cardinality_label_names' },
        { name: 'labelValuesCardinality', displayName: '"label value cardinality" queries', route: '/api/v1/cardinality_label_values', routeLabel: '_api_v1_cardinality_label_values' },
      ],
      local overviewRoutesRegex = '(prometheus|api_prom)(%s)' % std.join('|', [r.routeLabel for r in overviewRoutes]),
      overviewRoutesOverrides: [
        {
          matcher: {
            id: 'byRegexp',
            // To distinguish between query and query_range, we need to match the route with a negative lookahead.
            options: '/.*%s($|[^_])/' % r.routeLabel,
          },
          properties: [
            {
              id: 'displayName',
              value: r.displayName,
            },
          ],
        }
        for r in overviewRoutes
      ],
      overviewRoutesPerSecond: 'sum by (route) (rate(cortex_request_duration_seconds_count{%(queryFrontendMatcher)s,route=~"%(overviewRoutesRegex)s"}[$__rate_interval]))' % (variables { overviewRoutesRegex: overviewRoutesRegex }),
      nonOverviewRoutesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%(queryFrontendMatcher)s,route=~"(prometheus|api_prom)_api_v1_.*",route!~"%(overviewRoutesRegex)s"}[$__rate_interval]))' % (variables { overviewRoutesRegex: overviewRoutesRegex }),

      local queryPerSecond(name) = 'sum(rate(cortex_request_duration_seconds_count{%(queryFrontendMatcher)s,route=~"(prometheus|api_prom)%(route)s"}[$__rate_interval]))' %
                                   (variables { route: std.filter(function(r) r.name == name, overviewRoutes)[0].routeLabel }),
      instantQueriesPerSecond: queryPerSecond('instantQuery'),
      rangeQueriesPerSecond: queryPerSecond('rangeQuery'),
      labelNamesQueriesPerSecond: queryPerSecond('labelNames'),
      labelValuesQueriesPerSecond: queryPerSecond('labelValues'),
      seriesQueriesPerSecond: queryPerSecond('series'),
      remoteReadQueriesPerSecond: queryPerSecond('remoteRead'),
      metadataQueriesPerSecond: queryPerSecond('metadata'),
      exemplarsQueriesPerSecond: queryPerSecond('exemplars'),
      activeSeriesQueriesPerSecond: queryPerSecond('activeSeries'),
      labelNamesCardinalityQueriesPerSecond: queryPerSecond('labelNamesCardinality'),
      labelValuesCardinalityQueriesPerSecond: queryPerSecond('labelValuesCardinality'),

      // Read failures rate as percentage of total requests.
      readFailuresRate: $.nativeClassicFailureRate(p.readRequestsPerSecondMetric, p.readRequestsPerSecondSelector),
    },

    ruler: {
      evaluations: {
        successPerSecond:
          |||
            sum(rate(cortex_prometheus_rule_evaluations_total{%(rulerMatcher)s}[$__rate_interval]))
            -
            sum(rate(cortex_prometheus_rule_evaluation_failures_total{%(rulerMatcher)s}[$__rate_interval]))
          ||| % variables,
        failurePerSecond: 'sum(rate(cortex_prometheus_rule_evaluation_failures_total{%(rulerMatcher)s}[$__rate_interval]))' % variables,
        missedIterationsPerSecond: 'sum(rate(cortex_prometheus_rule_group_iterations_missed_total{%(rulerMatcher)s}[$__rate_interval]))' % variables,
        latency:
          |||
            sum (rate(cortex_prometheus_rule_evaluation_duration_seconds_sum{%(rulerMatcher)s}[$__rate_interval]))
              /
            sum (rate(cortex_prometheus_rule_evaluation_duration_seconds_count{%(rulerMatcher)s}[$__rate_interval]))
          ||| % variables,

        // Rule evaluation failures rate as percentage of total requests.
        failuresRate: |||
          (
            (
                sum(rate(cortex_prometheus_rule_evaluation_failures_total{%(rulerMatcher)s}[$__rate_interval]))
                +
                # Consider missed evaluations as failures.
                sum(rate(cortex_prometheus_rule_group_iterations_missed_total{%(rulerMatcher)s}[$__rate_interval]))
            )
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
          )
          /
          sum(rate(cortex_prometheus_rule_evaluations_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,
      },
      notifications: {
        // Notifications / sec attempted to send to the Alertmanager.
        totalPerSecond: |||
          sum(rate(cortex_prometheus_notifications_sent_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,

        // Notifications / sec successfully sent to the Alertmanager.
        successPerSecond: |||
          sum(rate(cortex_prometheus_notifications_sent_total{%(rulerMatcher)s}[$__rate_interval]))
            -
          sum(rate(cortex_prometheus_notifications_errors_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,

        // Notifications / sec failed to be sent to the Alertmanager.
        failurePerSecond: |||
          sum(rate(cortex_prometheus_notifications_errors_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,
      },
    },

    alertmanager: {
      notifications: {
        // Notifications / sec attempted to deliver by the Alertmanager to the receivers.
        totalPerSecond: |||
          sum(%(recordingRulePrefix)s_integration:cortex_alertmanager_notifications_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,

        // Notifications / sec successfully delivered by the Alertmanager to the receivers.
        successPerSecond: |||
          sum(%(recordingRulePrefix)s_integration:cortex_alertmanager_notifications_total:rate5m{%(alertmanagerMatcher)s})
          -
          sum(%(recordingRulePrefix)s_integration:cortex_alertmanager_notifications_failed_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,

        // Notifications / sec failed to be delivered by the Alertmanager to the receivers.
        failurePerSecond: |||
          sum(%(recordingRulePrefix)s_integration:cortex_alertmanager_notifications_failed_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,
      },
    },

    storage: {
      successPerSecond: |||
        sum(rate(thanos_objstore_bucket_operations_total{%(namespaceMatcher)s}[$__rate_interval]))
        -
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,
      failurePerSecond: |||
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,

      // Object storage operation failures rate as percentage of total operations.
      failuresRate: |||
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
        /
        sum(rate(thanos_objstore_bucket_operations_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,
    },
  },
}
