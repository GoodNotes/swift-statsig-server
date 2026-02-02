#pragma once

#include <string>

namespace statsig::swift
{
  struct Result
  {
    bool ok;
    std::string error;
  };

  struct BoolResult
  {
    bool ok;
    bool value;
    std::string error;
  };

  struct StringResult
  {
    bool ok;
    std::string value;
    std::string error;
  };

  bool isInitialized();
  Result initialize(const std::string &sdkKey);
  Result initializeWithOptions(
      const std::string &sdkKey,
      const std::string &api,
      bool localMode,
      int rulesetsSyncIntervalMs,
      int loggingIntervalMs,
      int loggingMaxBufferSize);
  Result shutdown();

  BoolResult checkGateJson(const std::string &userJson, const std::string &gateName);
  StringResult getConfigJson(const std::string &userJson, const std::string &configName);
  StringResult getExperimentJson(const std::string &userJson, const std::string &experimentName);
  StringResult getLayerJson(const std::string &userJson, const std::string &layerName);
  Result logEventJson(const std::string &userJson, const std::string &eventName);
}
