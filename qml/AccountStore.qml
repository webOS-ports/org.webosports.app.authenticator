/*
 * Copyright 2026 Herman van Hazendonk <github.com@herrie.org>
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 3, as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranties of
 * MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

import QtQuick

import "js/Accounts.js" as Accounts
import "js/Base32.js" as Base32

/*
 * The accounts, kept in the key manager (com.palm.keymanager): each
 * secret under a key of its own, the rest in an index (js/Accounts.js says
 * how). The key manager keeps every app's keys apart, by the app id of the
 * caller, and encrypts them on disk. Needs "keymanager-service.operation".
 *
 * bus: anything with LunaService's call(uri, json, reply, error). The
 * tests give it a stand-in.
 *
 * Nothing is written before the index has been read: if the key manager
 * cannot be reached, the app says so and leaves what is stored alone,
 * rather than starting over with nothing and writing that back.
 */
QtObject {
    id: store

    property var bus: null

    // "loading", "ready" or "failed".
    property string status: "loading"
    property string errorText: ""
    // The accounts in their order, without their secrets.
    property var accounts: []
    // A change that could not be saved, in words; "" when none.
    signal saveFailed(string message)

    readonly property string service: "luna://com.palm.keymanager/"

    // Secrets by account id, as normalized Base32. Kept in memory while the
    // app runs: every code needs one.
    property var _secrets: ({})
    // The decoded secrets, by id.
    property var _keys: ({})
    property int _generation: 0
    // The index key that holds the current generation, or -1 for none yet.
    property int _currentSlot: -1
    property var _queue: []
    property bool _busy: false

    // A call that the key manager never answers: give up after this long.
    property int timeoutMs: 20000

    function _call(method, params, done) {
        var finished = false;
        var timer = Qt.createQmlObject('import QtQuick; Timer { }', store);
        timer.interval = store.timeoutMs;
        timer.triggered.connect(function() {
            if (finished)
                return;
            finished = true;
            timer.destroy();
            done("The key manager did not answer.", null);
        });
        timer.start();
        function finish(error, payload) {
            if (finished)
                return;
            finished = true;
            timer.stop();
            timer.destroy();
            done(error, payload);
        }
        bus.call(service + method, JSON.stringify(params), function(message) {
            var payload;
            try {
                payload = JSON.parse(message.payload);
            } catch (e) {
                finish("The key manager gave an answer that could not be read.", null);
                return;
            }
            if (payload.returnValue === false)
                finish(payload.errorText || payload.message || "The key manager refused.", payload);
            else
                finish("", payload);
        }, function(error) {
            finish(String(error || "The key manager could not be reached."), null);
        });
    }

    function _isNotFound(error) {
        return /not found/i.test(error);
    }

    function secretOf(id) {
        return _secrets[id];
    }

    // The secret's bytes, for the codes.
    function keyOf(id) {
        return _keys[id] || null;
    }

    function accountById(id) {
        for (var i = 0; i < accounts.length; i++) {
            if (accounts[i].id === id)
                return accounts[i];
        }
        return null;
    }

    /*
     * Reads the index (both keys; the newer one counts) and then every
     * secret in it.
     */
    function load() {
        status = "loading";
        errorText = "";
        var results = [undefined, undefined];
        var failure = "";
        var pending = 2;
        Accounts.INDEX_KEYS.forEach(function(name, slot) {
            _call("fetchKey", { "keyname": name }, function(error, payload) {
                if (error !== "" && !_isNotFound(error))
                    failure = error;
                results[slot] = error === "" ? Accounts.parseIndex(payload.keydata) : null;
                if (error === "" && results[slot] === null)
                    console.warn("Authenticator: the index in " + name + " is damaged; using the other.");
                if (--pending === 0)
                    _indexRead(results, failure);
            });
        });
    }

    function _indexRead(results, failure) {
        if (failure !== "") {
            _fail("Could not read your accounts: " + failure);
            return;
        }
        var index = Accounts.newerIndex(results[0], results[1]);
        if (!index) {
            _generation = 0;
            _currentSlot = -1;
            _secrets = {};
            _keys = {};
            accounts = [];
            status = "ready";
            return;
        }
        _generation = index.generation;
        _currentSlot = index === results[0] ? 0 : 1;
        var list = index.accounts;
        var secrets = {}, keys = {};
        var pending = list.length;
        var missing = [];
        var problem = "";
        if (pending === 0) {
            _secrets = {};
            _keys = {};
            accounts = [];
            status = "ready";
            return;
        }
        list.forEach(function(account) {
            _call("fetchKey", { "keyname": Accounts.secretKeyName(account.id) }, function(error, payload) {
                if (error === "" && payload.keydata) {
                    secrets[account.id] = payload.keydata;
                    keys[account.id] = Base32.decode(payload.keydata);
                } else if (error !== "" && !_isNotFound(error)) {
                    problem = error;
                } else {
                    missing.push(account.id);
                }
                if (--pending > 0)
                    return;
                if (problem !== "") {
                    _fail("Could not read your accounts: " + problem);
                    return;
                }
                _secrets = secrets;
                _keys = keys;
                // An account whose secret is gone cannot make codes; it is
                // still listed, so it can be deleted and added again.
                if (missing.length > 0)
                    console.warn("Authenticator: " + missing.length + " account(s) without a secret");
                accounts = list;
                status = "ready";
            });
        });
    }

    function _fail(message) {
        errorText = message;
        status = "failed";
    }

    /*
     * Writes the next generation of the index, with `list`, into the key
     * that does not hold the current one: removes what is there, then
     * stores. done(error).
     */
    function _writeIndex(list, done) {
        var slot = _currentSlot === 0 ? 1 : 0;
        var name = Accounts.INDEX_KEYS[slot];
        var generation = _generation + 1;
        _call("remove", { "keyname": name }, function(error) {
            if (error !== "" && !_isNotFound(error)) {
                done(error);
                return;
            }
            _call("store", {
                "keyname": name,
                "keydata": Accounts.serializeIndex(generation, list),
                "type": "ASCIIBLOB",
                "nohide": true,
                "noexport": true
            }, function(storeError) {
                if (storeError !== "") {
                    done(storeError);
                    return;
                }
                _generation = generation;
                _currentSlot = slot;
                accounts = list;
                done("");
            });
        });
    }

    // One change at a time, in the order asked.
    function _enqueue(operation) {
        _queue.push(operation);
        _next();
    }

    function _next() {
        if (_busy || _queue.length === 0)
            return;
        _busy = true;
        var operation = _queue.shift();
        operation(function() {
            _busy = false;
            _next();
        });
    }

    function _ready(callback) {
        if (status !== "ready") {
            var message = "Your accounts have not been read, so nothing can be changed.";
            saveFailed(message);
            if (callback)
                callback(message);
            return false;
        }
        return true;
    }

    /*
     * Adds an account: its secret first, then the index naming it, so an
     * index never names a secret that is not there. callback(error, id).
     */
    function add(fields, callback) {
        if (!_ready(callback))
            return;
        _enqueue(function(next) {
            var id = Accounts.newId();
            var secret = Base32.normalize(fields.secret);
            _call("store", {
                "keyname": Accounts.secretKeyName(id),
                "keydata": secret,
                "type": "ASCIIBLOB",
                "nohide": true,
                "noexport": true
            }, function(error) {
                if (error !== "") {
                    _report("The account could not be saved: " + error, callback);
                    next();
                    return;
                }
                var list = accounts.concat([Accounts.metaFrom(fields, id)]);
                _writeIndex(list, function(indexError) {
                    if (indexError !== "") {
                        // Not listed, so not kept.
                        _call("remove", { "keyname": Accounts.secretKeyName(id) }, function() {});
                        _report("The account could not be saved: " + indexError, callback);
                    } else {
                        _setSecret(id, secret);
                        if (callback)
                            callback("", id);
                    }
                    next();
                });
            });
        });
    }

    /*
     * Changes an account. A new secret goes under a new id, the index is
     * written, and only then is the old secret removed.
     */
    function update(id, fields, callback) {
        if (!_ready(callback))
            return;
        _enqueue(function(next) {
            var index = _indexOf(id);
            if (index < 0) {
                _report("That account is no longer there.", callback);
                next();
                return;
            }
            var newSecret = fields.secret !== undefined && String(fields.secret).trim() !== ""
                    ? Base32.normalize(fields.secret) : "";
            var changesSecret = newSecret !== "" && newSecret !== _secrets[id];
            var newId = changesSecret ? Accounts.newId() : id;

            function writeIndex() {
                var list = accounts.slice(0);
                list[index] = Accounts.metaFrom(fields, newId);
                _writeIndex(list, function(error) {
                    if (error !== "") {
                        if (changesSecret)
                            _call("remove", { "keyname": Accounts.secretKeyName(newId) }, function() {});
                        _report("The change could not be saved: " + error, callback);
                        next();
                        return;
                    }
                    if (changesSecret) {
                        _call("remove", { "keyname": Accounts.secretKeyName(id) }, function() {});
                        _setSecret(newId, newSecret);
                        _setSecret(id, undefined);
                    }
                    if (callback)
                        callback("", newId);
                    next();
                });
            }

            if (!changesSecret) {
                writeIndex();
                return;
            }
            _call("store", {
                "keyname": Accounts.secretKeyName(newId),
                "keydata": newSecret,
                "type": "ASCIIBLOB",
                "nohide": true,
                "noexport": true
            }, function(error) {
                if (error !== "") {
                    _report("The change could not be saved: " + error, callback);
                    next();
                    return;
                }
                writeIndex();
            });
        });
    }

    // Removes an account: from the index first, then its secret.
    function remove(id, callback) {
        if (!_ready(callback))
            return;
        _enqueue(function(next) {
            var list = accounts.filter(function(a) { return a.id !== id; });
            if (list.length === accounts.length) {
                if (callback)
                    callback("");
                next();
                return;
            }
            _writeIndex(list, function(error) {
                if (error !== "") {
                    _report("The account could not be deleted: " + error, callback);
                } else {
                    _call("remove", { "keyname": Accounts.secretKeyName(id) }, function() {});
                    _setSecret(id, undefined);
                    if (callback)
                        callback("");
                }
                next();
            });
        });
    }

    function move(from, to, callback) {
        if (!_ready(callback))
            return;
        _enqueue(function(next) {
            var list = Accounts.moved(accounts, from, to);
            _writeIndex(list, function(error) {
                if (error !== "")
                    _report("The new order could not be saved: " + error, callback);
                else if (callback)
                    callback("");
                next();
            });
        });
    }

    /*
     * A counter-based account's next code: the counter goes up and is
     * saved first, so a code is never shown twice even if the app is
     * closed straight after. callback(error, counter) with the counter the
     * shown code is for.
     */
    function advanceCounter(id, callback) {
        if (!_ready(callback))
            return;
        _enqueue(function(next) {
            var index = _indexOf(id);
            if (index < 0) {
                _report("That account is no longer there.", callback);
                next();
                return;
            }
            var list = accounts.slice(0);
            var changed = Accounts.metaFrom(list[index], id);
            changed.counter = list[index].counter + 1;
            list[index] = changed;
            _writeIndex(list, function(error) {
                if (error !== "")
                    _report("The counter could not be saved, so no new code: " + error, callback);
                else if (callback)
                    callback("", changed.counter - 1);
                next();
            });
        });
    }

    function _indexOf(id) {
        for (var i = 0; i < accounts.length; i++) {
            if (accounts[i].id === id)
                return i;
        }
        return -1;
    }

    function _setSecret(id, secret) {
        var secrets = Object.assign({}, _secrets);
        var keys = Object.assign({}, _keys);
        if (secret === undefined) {
            delete secrets[id];
            delete keys[id];
        } else {
            secrets[id] = secret;
            keys[id] = Base32.decode(secret);
        }
        _secrets = secrets;
        _keys = keys;
    }

    function _report(message, callback) {
        saveFailed(message);
        if (callback)
            callback(message);
    }
}
