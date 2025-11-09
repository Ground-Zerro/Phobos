#!/usr/bin/env python3

import http.server
import socketserver
import os
import sys
from urllib.parse import urlparse, unquote

class SecureHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):

    def list_directory(self, path):
        self.send_error(403, "Directory listing is forbidden")
        return None

    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = unquote(parsed_path.path)

        if path == '/':
            self.serve_index()
            return

        file_path = os.path.normpath(os.path.join(self.directory, path.lstrip('/')))

        if not file_path.startswith(os.path.abspath(self.directory)):
            self.send_error(403, "Access denied")
            return

        if os.path.isdir(file_path):
            self.send_error(403, "Directory listing is forbidden")
            return

        if os.path.isfile(file_path):
            super().do_GET()
        else:
            self.send_error(404, "File not found")

    def serve_index(self):
        index_path = os.path.join(self.directory, 'index.html')
        if os.path.isfile(index_path):
            super().do_GET()
        else:
            self.send_error(404, "Index not found")

    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format % args))

def run_server(port, directory):
    os.chdir(directory)

    handler = SecureHTTPRequestHandler
    handler.directory = directory

    with socketserver.TCPServer(("", port), handler) as httpd:
        print(f"Serving at port {port}")
        print(f"Directory: {directory}")
        print(f"Directory listing: DISABLED")
        httpd.serve_forever()

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: phobos-http-server.py <port> <directory>")
        sys.exit(1)

    port = int(sys.argv[1])
    directory = sys.argv[2]

    if not os.path.isdir(directory):
        print(f"Error: Directory {directory} does not exist")
        sys.exit(1)

    try:
        run_server(port, directory)
    except KeyboardInterrupt:
        print("\nServer stopped.")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
