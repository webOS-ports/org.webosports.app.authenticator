/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick

/*
 * com.palm.keymanager as the app sees it, for the tests: store, fetchKey,
 * remove, with the real one's rules as its source has them
 * (webOS-ports/keymanager, service/javascript): store refuses a
 * name that is taken ("Key already exists."), fetchKey and remove answer
 * "Key not found" for one that is not, and fetchKey hands keydata back only
 * for a key stored with nohide. The error texts are the real service's
 * (the mindphone answered a missing key with "MojoService: no errorCode
 * supplied Key not found", errorCode -9999). Answers come later, not
 * inside the call, as over the bus.
 *
 * Knobs: failMethods ({ "store": "Denied method call" }) makes those
 * methods fail; silent makes it answer nothing at all; failAfter fails
 * every call after that many; failStoreOf fails storing keys whose names
 * start with it.
 */
QtObject {
    id: fake

    property var keys: ({})
    property var calls: []
    property var failMethods: ({})
    property bool silent: false
    property int failAfter: -1
    // Fails store for key names starting with this ("" for none).
    property string failStoreOf: ""

    function call(uri, json, reply, error) {
        var method = uri.replace(/^luna:\/\/com\.palm\.keymanager\//, "");
        var args = JSON.parse(json);
        calls.push({ method: method, args: args });
        if (silent)
            return {};
        var answer;
        if (failAfter >= 0 && calls.length > failAfter)
            answer = { returnValue: false, errorText: "Simulated failure" };
        else if (method === "store" && failStoreOf !== "" && String(args.keyname).indexOf(failStoreOf) === 0)
            answer = { returnValue: false, errorText: "Simulated failure" };
        else if (failMethods[method] !== undefined)
            answer = { returnValue: false, errorText: failMethods[method] };
        else
            answer = handle(method, args);
        Qt.callLater(function() { reply({ payload: JSON.stringify(answer) }); });
        return {};
    }

    function handle(method, args) {
        if (uriIsUnknown(method))
            return { returnValue: false, errorText: "Unknown method" };
        var k;
        if (method === "store") {
            if (!args.keyname || !args.keydata || !args.type)
                return { returnValue: false, errorText: "Need keyname, keydata and type" };
            if (keys[args.keyname] !== undefined)
                return { returnValue: false, errorText: "MojoService: no errorCode supplied Key already exists." };
            k = Object.assign({}, keys);
            k[args.keyname] = { keydata: args.keydata, type: args.type, nohide: args.nohide === true,
                                noexport: args.noexport === true };
            keys = k;
            return { returnValue: true };
        }
        if (method === "fetchKey") {
            var key = keys[args.keyname];
            if (key === undefined)
                return { returnValue: false, errorText: "MojoService: no errorCode supplied Key not found" };
            var out = { returnValue: true, keyname: args.keyname, type: key.type, nohide: key.nohide };
            if (key.nohide)
                out.keydata = key.keydata;
            return out;
        }
        if (method === "remove") {
            if (keys[args.keyname] === undefined)
                return { returnValue: false, errorText: "MojoService: no errorCode supplied Key not found." };
            k = Object.assign({}, keys);
            delete k[args.keyname];
            keys = k;
            return { returnValue: true };
        }
        return { returnValue: false, errorText: "Unknown method" };
    }

    function uriIsUnknown(method) {
        return ["store", "fetchKey", "remove"].indexOf(method) < 0;
    }

    function countOf(method) {
        return calls.filter(function(c) { return c.method === method; }).length;
    }
}
