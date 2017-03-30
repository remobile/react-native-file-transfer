/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
*/
'use strict';

const argscheck = require('@remobile/react-native-cordova').argscheck,
    exec = require('@remobile/react-native-cordova').exec,
    FileTransferError = require('./FileTransferError'),
    ProgressEvent = require('@remobile/react-native-cordova').ProgressEvent;

const { NativeEventEmitter, DeviceEventEmitter, Platform, NativeModules } = require('react-native');
const EventEmitter = Platform.OS === 'android' ? DeviceEventEmitter : new NativeEventEmitter(NativeModules.FileTransfer);

function newProgressEvent (result) {
    const pe = new ProgressEvent();
    pe.lengthComputable = result.lengthComputable;
    pe.loaded = result.loaded;
    pe.total = result.total;
    return pe;
}

function getUrlCredentials (urlString) {
    const credentialsPattern = /^https?:\/\/(?:(?:(([^:@/]*)(?::([^@/]*))?)?@)?([^:/?#]*)(?::(\d*))?).*$/,
        credentials = credentialsPattern.exec(urlString);

    return credentials && credentials[1];
}

function getBasicAuthHeader (urlString) {
    let header = null;

    // This is changed due to MS Windows doesn't support credentials in http uris
    // so we detect them by regexp and strip off from result url
    // Proof: http://social.msdn.microsoft.com/Forums/windowsapps/en-US/a327cf3c-f033-4a54-8b7f-03c56ba3203f/windows-foundation-uri-security-problem

    if (false) {
        const credentials = getUrlCredentials(urlString);
        if (credentials) {
            const authHeader = 'Authorization';
            const authHeaderValue = 'Basic ' + window.btoa(credentials);

            header = {
                name : authHeader,
                value : authHeaderValue,
            };
        }
    }

    return header;
}

function convertHeadersToArray (headers) {
    const result = [];
    for (const header in headers) {
        if (headers.hasOwnProperty(header)) {
            const headerValue = headers[header];
            result.push({
                name: header,
                value: headerValue.toString(),
            });
        }
    }
    return result;
}

let idCounter = 0;

/**
 * FileTransfer uploads a file to a remote server.
 * @constructor
 */
const FileTransfer = function () {
    this._id = ++idCounter;
    this.onprogress = null; // optional callback
};

/**
* Given an absolute file path, uploads a file on the device to a remote server
* using a multipart HTTP request.
* @param filePath {String}           Full path of the file on the device
* @param server {String}             URL of the server to receive the file
* @param successCallback (Function}  Callback to be invoked when upload has completed
* @param errorCallback {Function}    Callback to be invoked upon error
* @param options {FileUploadOptions} Optional parameters such as file name and mimetype
* @param trustAllHosts {Boolean} Optional trust all hosts (e.g. for self-signed certs), defaults to false
*/
FileTransfer.prototype.upload = function (filePath, server, successCallback, errorCallback, options, trustAllHosts) {
    argscheck.checkArgs('ssFFO*', 'FileTransfer.upload', arguments);
    let subscription;

    // check for options
    let fileKey = null;
    let fileName = null;
    let mimeType = null;
    let params = null;
    let chunkedMode = true;
    let headers = null;
    let httpMethod = null;
    let basicAuthHeader = getBasicAuthHeader(server);
    if (basicAuthHeader) {
        server = server.replace(getUrlCredentials(server) + '@', '');

        options = options || {};
        options.headers = options.headers || {};
        options.headers[basicAuthHeader.name] = basicAuthHeader.value;
    }

    if (options) {
        fileKey = options.fileKey;
        fileName = options.fileName;
        mimeType = options.mimeType;
        headers = options.headers;
        httpMethod = options.httpMethod || 'POST';
        if (httpMethod.toUpperCase() == 'PUT') {
            httpMethod = 'PUT';
        } else {
            httpMethod = 'POST';
        }
        if (options.chunkedMode !== null || typeof options.chunkedMode != 'undefined') {
            chunkedMode = options.chunkedMode;
        }
        if (options.params) {
            params = options.params;
        } else {
            params = {};
        }
    }

    if (false) {
        headers = headers && convertHeadersToArray(headers);
        params = params && convertHeadersToArray(params);
    }

    const fail = errorCallback && function (e) {
        const error = new FileTransferError(e.code, e.source, e.target, e.http_status, e.body, e.exception);
        subscription && subscription.remove();
        errorCallback(error);
    };

    const win = successCallback && function (result) {
        subscription && subscription.remove();
        successCallback(result);
    };

    if (this.onprogress) {
        const self = this;
        subscription = EventEmitter.addListener('UploadProgress-' + this._id, function (result) {
            self.onprogress(newProgressEvent(result));
        });
    }
    console.log(filePath, server, fileKey, fileName, mimeType, params, trustAllHosts, chunkedMode, headers, this._id, httpMethod);
    exec(win, fail, 'FileTransfer', 'upload', [filePath, server, fileKey, fileName, mimeType, params, trustAllHosts, chunkedMode, headers, this._id, httpMethod]);
};

/**
 * Downloads a file form a given URL and saves it to the specified directory.
 * @param source {String}          URL of the server to receive the file
 * @param target {String}         Full path of the file on the device
 * @param successCallback (Function}  Callback to be invoked when upload has completed
 * @param errorCallback {Function}    Callback to be invoked upon error
 * @param trustAllHosts {Boolean} Optional trust all hosts (e.g. for self-signed certs), defaults to false
 * @param options {FileDownloadOptions} Optional parameters such as headers
 */
FileTransfer.prototype.download = function (source, target, successCallback, errorCallback, trustAllHosts, options) {
    argscheck.checkArgs('ssFF*', 'FileTransfer.download', arguments);
    const self = this;
    let subscription;

    const basicAuthHeader = getBasicAuthHeader(source);
    if (basicAuthHeader) {
        source = source.replace(getUrlCredentials(source) + '@', '');

        options = options || {};
        options.headers = options.headers || {};
        options.headers[basicAuthHeader.name] = basicAuthHeader.value;
    }

    let headers = null;
    if (options) {
        headers = options.headers || null;
    }

    if (false && headers) {
        headers = convertHeadersToArray(headers);
    }

    const win = successCallback && function (result) {
        subscription && subscription.remove();
        successCallback(result);
    };

    const fail = errorCallback && function (e) {
        subscription && subscription.remove();
        const error = new FileTransferError(e.code, e.source, e.target, e.http_status, e.body, e.exception);
        errorCallback(error);
    };

    if (this.onprogress) {
        subscription = EventEmitter.addListener('DownloadProgress-' + this._id, function (result) {
            self.onprogress(newProgressEvent(result));
        });
    }

    exec(win, fail, 'FileTransfer', 'download', [source, target, trustAllHosts, this._id, headers]);
};

/**
 * Aborts the ongoing file transfer on this object. The original error
 * callback for the file transfer will be called if necessary.
 */
FileTransfer.prototype.abort = function () {
    exec(null, null, 'FileTransfer', 'abort', [this._id]);
};

module.exports = FileTransfer;
