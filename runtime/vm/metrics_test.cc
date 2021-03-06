// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "platform/assert.h"

#include "include/dart_api.h"
#include "include/dart_tools_api.h"

#include "vm/dart_api_impl.h"
#include "vm/dart_api_state.h"
#include "vm/globals.h"
#include "vm/json_stream.h"
#include "vm/metrics.h"
#include "vm/unit_test.h"

namespace dart {

#ifndef PRODUCT

VM_UNIT_TEST_CASE(Metric_Simple) {
  TestCase::CreateTestIsolate();
  {
    Metric metric;

    // Initialize metric.
    metric.InitInstance(Isolate::Current(), "a.b.c", "foobar",
                        Metric::kCounter);
    EXPECT_EQ(0, metric.value());
    metric.increment();
    EXPECT_EQ(1, metric.value());
    metric.set_value(44);
    EXPECT_EQ(44, metric.value());
  }
  Dart_ShutdownIsolate();
}

class MyMetric : public Metric {
 protected:
  int64_t Value() const {
    // 99 bytes.
    return 99;
  }

 public:
  // Just used for testing.
  int64_t LeakyValue() const { return Value(); }
};

VM_UNIT_TEST_CASE(Metric_OnDemand) {
  TestCase::CreateTestIsolate();
  {
    Thread* thread = Thread::Current();
    TransitionNativeToVM transition(thread);
    StackZone zone(thread);
    HANDLESCOPE(thread);
    MyMetric metric;

    metric.InitInstance(Isolate::Current(), "a.b.c", "foobar", Metric::kByte);
    // value is still the default value.
    EXPECT_EQ(0, metric.value());
    // Call LeakyValue to confirm that Value returns constant 99.
    EXPECT_EQ(99, metric.LeakyValue());

    // Serialize to JSON.
    JSONStream js;
    metric.PrintJSON(&js);
    const char* json = js.ToCString();
    EXPECT_STREQ(
        "{\"type\":\"Counter\",\"name\":\"a.b.c\",\"description\":"
        "\"foobar\",\"unit\":\"byte\","
        "\"fixedId\":true,\"id\":\"metrics\\/native\\/a.b.c\""
        ",\"value\":99.0}",
        json);
  }
  Dart_ShutdownIsolate();
}

ISOLATE_UNIT_TEST_CASE(Metric_EmbedderAPI) {
  {
    TransitionVMToNative transition(Thread::Current());

    const char* kScript = "void main() {}";
    Dart_Handle api_lib = TestCase::LoadTestScript(
        kScript, /*resolver=*/nullptr, RESOLVED_USER_TEST_URI);
    EXPECT_VALID(api_lib);
  }

  // Ensure we've done new/old GCs to ensure max metrics are initialized.
  String::New("<land-in-new-space>", Heap::kNew);
  Isolate::Current()->heap()->new_space()->Scavenge();
  Isolate::Current()->heap()->CollectAllGarbage(Heap::kLowMemory);

  // Ensure we've something live in new space.
  String::New("<land-in-new-space2>", Heap::kNew);

  {
    TransitionVMToNative transition(Thread::Current());

    Dart_Isolate isolate = Dart_CurrentIsolate();
    EXPECT(Dart_VMIsolateCountMetric() > 0);
    EXPECT(Dart_IsolateHeapOldUsedMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapOldUsedMaxMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapOldCapacityMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapOldCapacityMaxMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapNewUsedMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapNewUsedMaxMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapNewCapacityMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapNewCapacityMaxMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapGlobalUsedMetric(isolate) > 0);
    EXPECT(Dart_IsolateHeapGlobalUsedMaxMetric(isolate) > 0);
  }
}

#endif  // !PRODUCT

}  // namespace dart
