namespace JsonX {
    string Lookup_StringOrDefault(Json::Value &in obj, const string &in key, const string &in defaultValue, bool logOnFailure = false) {
        try {
            return string(obj[key]);
        } catch {
            if (logOnFailure) {
                trace("JsonX: Lookup_StringOrDefault: key '" + key + "' not found in object: " + Json::Write(obj) + " / Error: " + getExceptionInfo());
            }
            return defaultValue;
        }
    }
}