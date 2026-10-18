# Batch 7 — তিন agent-এর starter

> **ঐতিহাসিক প্রস্তাব—এই starter এখন চালাবেন না।** A/B-এর আগের দুই-worker কাজ reviewed; Captain foundation-সহ বর্তমান অবস্থা `docs/BATCH_7.md` ও final report-এ। নতুন কাজের জন্য নতুন Captain brief লাগবে। নিচের লেখা শুধু পুরোনো পরিকল্পনার রেকর্ড।

প্রতিটি block আলাদা A/B/C chat-এ paste করুন। আগের worker workspace থাকলে সেটিই
ব্যবহার করুন—নিজের saved login reuse হবে। একেবারে নতুন workspace হলে approval
লাগতে পারে। **Captain এখনও worker চালু করেননি; এই prompt দিয়েই আপনি শুরু করবেন।**

ফাইল download/upload করতে হবে না। প্রত্যেকে নিজের branch push করবে; Captain
Git থেকে diff নিয়ে review ও integration করবেন। `main`, CI ও release worker-এর কাজ নয়।

## Agent A — reminder reconciliation

```text
তুমি Karmopath-এর Agent A, Batch 7। Repo: https://github.com/Keshab1997/karmopath.git
নিজের existing workspace/login reuse করো। origin/main-এর AGENTS.md, docs/DISPATCH_BATCH_7.md, docs/BATCH_7_CONTRACTS.md এবং docs/briefs/AGENT_A_BATCH_7.md আগে পুরো পড়ো।
Frozen base bffcfb473d14f66bf47b85be96558497cc387dc4 থেকে agent/A/reminder-reconcile-v1 branch-এ শুধু ওই brief-এর কাজ করো। অন্য worker-এর code-এর জন্য অপেক্ষা বা তার implementation import করবে না।
নিজের allowed files, focused checks ও পাঁচ লাইনের report দিয়ে branch push করো। main/build/CI/release নয়। প্রয়োজনীয় shared change হলে থেমে Captain-কে blocked report দাও।
```

## Agent B — Android notifications

```text
তুমি Karmopath-এর Agent B, Batch 7। Repo: https://github.com/Keshab1997/karmopath.git
নিজের existing workspace/login reuse করো। origin/main-এর AGENTS.md, docs/DISPATCH_BATCH_7.md, docs/BATCH_7_CONTRACTS.md এবং docs/briefs/AGENT_B_BATCH_7.md আগে পুরো পড়ো।
Frozen base bffcfb473d14f66bf47b85be96558497cc387dc4 থেকে agent/B/android-reminders-v1 branch-এ শুধু ওই brief-এর কাজ করো। এটি নতুন notification namespace-এর assignment, পুরোনো UI batch নয়; অন্য worker-এর implementation import করবে না।
নিজের allowed files, focused checks ও পাঁচ লাইনের report দিয়ে branch push করো। main/build/CI/release নয়। Android config/dependency বদল দরকার হলে থেমে Captain-কে blocked report দাও।
```

## Agent C — native runtime factory

```text
তুমি Karmopath-এর Agent C, Batch 7। Repo: https://github.com/Keshab1997/karmopath.git
নিজের existing workspace/login reuse করো। origin/main-এর AGENTS.md, docs/DISPATCH_BATCH_7.md, docs/BATCH_7_CONTRACTS.md এবং docs/briefs/AGENT_C_BATCH_7.md আগে পুরো পড়ো।
Frozen base bffcfb473d14f66bf47b85be96558497cc387dc4 থেকে agent/C/native-runtime-v1 branch-এ শুধু ওই brief-এর কাজ করো। এটি native factory assignment, পুরোনো admin batch নয়; A/B implementation নয়, frozen ports ও injected factories ব্যবহার করবে।
নিজের allowed files, focused checks ও পাঁচ লাইনের report দিয়ে branch push করো। main/build/CI/release নয়; production feed URL বানাবে না। shared API দরকার হলে থেমে Captain-কে blocked report দাও।
```

## এরপর

কাজ শেষ হলে তাদের পাঁচ লাইনের report Captain-কে দিন; code আলাদা করে পাঠানোর
দরকার নেই। Captain actual pushed diff দেখবেন, gate চালাবেন, একেকটি stream integrate
করবেন। Production feed approval এবং real Android device-এর permission/reboot/
delivery যাচাই এখনো বাকি—foundation tests এগুলোর প্রমাণ নয়।
