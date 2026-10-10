"""Publish simulated PCBA line test-station telemetry to AWS IoT Core (topic vn/pcbaquality/telemetry).

The IoT rule lands each message in S3; Snowpipe loads it into RAW.LIVE_TELEMETRY.
Line IDs come from RAW.LINES (SMT-0000..SMT-0023). Values are seeded random.
"""
import argparse
import json
import random
from datetime import datetime, timezone


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--region', default='us-west-2')
    ap.add_argument('--count', type=int, default=40)
    ap.add_argument('--seed', type=int)
    args = ap.parse_args()
    import boto3
    iot = boto3.client('iot', region_name=args.region)
    endpoint = iot.describe_endpoint(endpointType='iot:Data-ATS')['endpointAddress']
    data = boto3.client('iot-data', region_name=args.region, endpoint_url=f'https://{endpoint}')
    rng = random.Random(args.seed)
    for _ in range(args.count):
        line = f'SMT-{rng.randint(0, 23):04d}'
        alarm = rng.random() < 0.1
        msg = {'line_id': line,
               'event_ts': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3],
               'ctq_dev_pct': round(rng.gauss(6.8 if alarm else 1.6, 0.6), 2),
               'board_temp_c': round(rng.gauss(41 if alarm else 32, 1.5), 1),
               'status': 'ALARM' if alarm else 'RUNNING'}
        data.publish(topic='vn/pcbaquality/telemetry', qos=1, payload=json.dumps(msg))
    print(f'published {args.count} messages to vn/pcbaquality/telemetry via {endpoint}')


if __name__ == '__main__':
    main()
