#include "statsig_swift.h"

#include <exception>

#include <nlohmann/json.hpp>

#include "json.h"
#include "statsig.h"

namespace
{
  nlohmann::json default_user_json()
  {
    return nlohmann::json{
        {"userID", ""},
        {"email", ""},
        {"ipAddress", ""},
        {"userAgent", ""},
        {"country", ""},
        {"locale", ""},
        {"appVersion", ""},
        {"custom", nlohmann::json::object()},
        {"privateAttribute", nlohmann::json::object()},
        {"statsigEnvironment", nlohmann::json::object()},
        {"customIDs", nlohmann::json::object()},
    };
  }

  bool parse_user_json(const std::string &user_json, statsig::User &user, std::string &error)
  {
    try
    {
      nlohmann::json merged = default_user_json();
      if (!user_json.empty())
      {
        nlohmann::json input = nlohmann::json::parse(user_json);
        if (!input.is_object())
        {
          error = "userJson must be a JSON object";
          return false;
        }
        merged.merge_patch(input);
      }
      user = merged.get<statsig::User>();
      return true;
    }
    catch (const std::exception &ex)
    {
      error = ex.what();
      return false;
    }
    catch (...)
    {
      error = "Failed to parse userJson";
      return false;
    }
  }

  statsig::swift::Result not_initialized_result()
  {
    return statsig::swift::Result{false, "Statsig not initialized"};
  }
}

namespace statsig::swift
{
  bool isInitialized()
  {
    return statsig::isInitialized();
  }

  Result initialize(const std::string &sdkKey)
  {
    if (statsig::isInitialized())
    {
      return Result{false, "Statsig already initialized"};
    }
    statsig::initialize(sdkKey);
    return Result{true, ""};
  }

  Result initializeWithOptions(
      const std::string &sdkKey,
      const std::string &api,
      bool localMode,
      int rulesetsSyncIntervalMs,
      int loggingIntervalMs,
      int loggingMaxBufferSize)
  {
    if (statsig::isInitialized())
    {
      return Result{false, "Statsig already initialized"};
    }
    statsig::Options options;
    if (!api.empty())
    {
      options.api = api;
    }
    options.localMode = localMode;
    options.rulesetsSyncIntervalMs = rulesetsSyncIntervalMs;
    options.loggingIntervalMs = loggingIntervalMs;
    options.loggingMaxBufferSize = loggingMaxBufferSize;
    statsig::initialize(sdkKey, options);
    return Result{true, ""};
  }

  Result shutdown()
  {
    if (!statsig::isInitialized())
    {
      return not_initialized_result();
    }
    statsig::shutdown();
    return Result{true, ""};
  }

  BoolResult checkGateJson(const std::string &userJson, const std::string &gateName)
  {
    if (!statsig::isInitialized())
    {
      return BoolResult{false, false, "Statsig not initialized"};
    }
    statsig::User user;
    std::string error;
    if (!parse_user_json(userJson, user, error))
    {
      return BoolResult{false, false, error};
    }
    try
    {
      bool value = statsig::checkGate(user, gateName);
      return BoolResult{true, value, ""};
    }
    catch (const std::exception &ex)
    {
      return BoolResult{false, false, ex.what()};
    }
    catch (...)
    {
      return BoolResult{false, false, "Failed to check gate"};
    }
  }

  StringResult getConfigJson(const std::string &userJson, const std::string &configName)
  {
    if (!statsig::isInitialized())
    {
      return StringResult{false, "", "Statsig not initialized"};
    }
    statsig::User user;
    std::string error;
    if (!parse_user_json(userJson, user, error))
    {
      return StringResult{false, "", error};
    }
    try
    {
      statsig::DynamicConfig config = statsig::getConfig(user, configName);
      nlohmann::json json = config;
      return StringResult{true, json.dump(), ""};
    }
    catch (const std::exception &ex)
    {
      return StringResult{false, "", ex.what()};
    }
    catch (...)
    {
      return StringResult{false, "", "Failed to get config"};
    }
  }

  StringResult getExperimentJson(const std::string &userJson, const std::string &experimentName)
  {
    if (!statsig::isInitialized())
    {
      return StringResult{false, "", "Statsig not initialized"};
    }
    statsig::User user;
    std::string error;
    if (!parse_user_json(userJson, user, error))
    {
      return StringResult{false, "", error};
    }
    try
    {
      statsig::DynamicConfig config = statsig::getExperiment(user, experimentName);
      nlohmann::json json = config;
      return StringResult{true, json.dump(), ""};
    }
    catch (const std::exception &ex)
    {
      return StringResult{false, "", ex.what()};
    }
    catch (...)
    {
      return StringResult{false, "", "Failed to get experiment"};
    }
  }

  StringResult getLayerJson(const std::string &userJson, const std::string &layerName)
  {
    if (!statsig::isInitialized())
    {
      return StringResult{false, "", "Statsig not initialized"};
    }
    statsig::User user;
    std::string error;
    if (!parse_user_json(userJson, user, error))
    {
      return StringResult{false, "", error};
    }
    try
    {
      statsig::Layer layer = statsig::getLayer(user, layerName);
      nlohmann::json json = nlohmann::json::object();
      json["name"] = layer.name;
      json["value"] = layer.value;
      json["ruleID"] = layer.ruleID;
      return StringResult{true, json.dump(), ""};
    }
    catch (const std::exception &ex)
    {
      return StringResult{false, "", ex.what()};
    }
    catch (...)
    {
      return StringResult{false, "", "Failed to get layer"};
    }
  }

  Result logEventJson(const std::string &userJson, const std::string &eventName)
  {
    if (!statsig::isInitialized())
    {
      return not_initialized_result();
    }
    statsig::User user;
    std::string error;
    if (!parse_user_json(userJson, user, error))
    {
      return Result{false, error};
    }
    try
    {
      statsig::logEvent(user, eventName);
      return Result{true, ""};
    }
    catch (const std::exception &ex)
    {
      return Result{false, ex.what()};
    }
    catch (...)
    {
      return Result{false, "Failed to log event"};
    }
  }
}
