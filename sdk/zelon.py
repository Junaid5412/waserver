"""Python 3.10+ standard-library Zelon client. Never automatically retry sends."""
import json
import uuid
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path

class ZelonError(Exception):
    def __init__(self, status, body):
        self.status, self.body = status, body
        super().__init__(body.get("error", f"HTTP {status}"))

class Zelon:
    def __init__(self, url, instance_id, api_key, timeout=30):
        self.url = url.rstrip('/') + '/api/instances/' + urllib.parse.quote(instance_id)
        self.key, self.timeout = api_key, timeout

    def request(self, path, method='GET', body=None, key=None, raw=False):
        headers = {'Authorization': 'Bearer ' + self.key}
        data = None
        if body is not None:
            headers['Content-Type'] = 'application/octet-stream' if raw else 'application/json'
            data = body if raw else json.dumps(body).encode()
        if key:
            headers['Idempotency-Key'] = key
        req = urllib.request.Request(self.url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                return json.load(res)
        except urllib.error.HTTPError as e:
            try:
                body = json.load(e)
            except ValueError:
                body = {'error': f'HTTP {e.code}'}
            raise ZelonError(e.code, body) from e

    def send(self, message, key=None):
        return self.request('/messages', 'POST', message, key or str(uuid.uuid4()))

    def upload(self, filename, mimetype='application/octet-stream'):
        file = Path(filename)
        media = self.request('/media', 'POST', {'filename': file.name, 'size': file.stat().st_size, 'mimetype': mimetype})
        with file.open('rb') as stream:
            for i in range(media['totalChunks']):
                self.request(f"/media/{media['id']}/chunks/{i}", 'PUT', stream.read(media['chunkSize']), raw=True)
        return self.request(f"/media/{media['id']}/complete", 'POST', {})
