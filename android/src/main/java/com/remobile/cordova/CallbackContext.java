/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/
package com.remobile.cordova;

import org.json.JSONArray;
import com.facebook.react.bridge.Callback;
import org.json.JSONException;
import org.json.JSONObject;

public class CallbackContext {

    private static final String LOG_TAG = "CordovaPlugin";

    private Callback success;
    private Callback error;

    public CallbackContext(Callback success, Callback error) {
        this.success = success;
        this.error = error;
    }


    public void sendPluginResult(PluginResult pluginResult) {
        int messageType = pluginResult.messageType;
        Callback callback = pluginResult.status.equals(PluginResult.Status.OK) ? success : error;
        try {
            switch (messageType) {
                case PluginResult.MESSAGE_TYPE_JSON_ARRAY:
                    callback.invoke(JsonConvert.jsonToReact(pluginResult.jsonArrayMessage));
                    break;
                case PluginResult.MESSAGE_TYPE_JSON_OBJECT:
                    callback.invoke(JsonConvert.jsonToReact(pluginResult.jsonObjectMessage));
                    break;
                default:
                    callback.invoke(pluginResult.stringMessage);
                    break;
            }
        } catch (JSONException ex) {
            error.invoke("Internal error converting results:" + ex.getMessage());
        }
    }

    /**
     * Helper for success callbacks that just returns the Status.OK by default
     *
     * @param message The message to add to the success result.
     */
    public void success(JSONObject message) {
        sendPluginResult(new PluginResult(PluginResult.Status.OK, message));
    }

    /**
     * Helper for success callbacks that just returns the Status.OK by default
     *
     * @param message The message to add to the success result.
     */
    public void success(String message) {
        sendPluginResult(new PluginResult(PluginResult.Status.OK, message));
    }

    /**
     * Helper for success callbacks that just returns the Status.OK by default
     *
     * @param message The message to add to the success result.
     */
    public void success(JSONArray message) {
        sendPluginResult(new PluginResult(PluginResult.Status.OK, message));
    }

    /**
     * Helper for success callbacks that just returns the Status.OK by default
     *
     * @param message The message to add to the success result.
     */
    public void success(int message) {
        sendPluginResult(new PluginResult(PluginResult.Status.OK, message));
    }

    /**
     * Helper for success callbacks that just returns the Status.OK by default
     */
    public void success() {
        sendPluginResult(new PluginResult(PluginResult.Status.OK));
    }

    /**
     * Helper for error callbacks that just returns the Status.ERROR by default
     *
     * @param message The message to add to the error result.
     */
    public void error(JSONObject message) {
        sendPluginResult(new PluginResult(PluginResult.Status.ERROR, message));
    }

    /**
     * Helper for error callbacks that just returns the Status.ERROR by default
     *
     * @param message The message to add to the error result.
     */
    public void error(String message) {
        sendPluginResult(new PluginResult(PluginResult.Status.ERROR, message));
    }

    /**
     * Helper for error callbacks that just returns the Status.ERROR by default
     *
     * @param message The message to add to the error result.
     */
    public void error(int message) {
        sendPluginResult(new PluginResult(PluginResult.Status.ERROR, message));
    }
}
