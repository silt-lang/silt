The Outer Core library implements the GraphIR optimizer and scheduler.

Optimizing GraphIR
===============

Optimizing GraphIR is slightly different than optimizing traditional SSA IRs.  GraphIR comes in
two distinct flavors: scheduled and unscheduled.  The unscheduled Sea-of-Nodes form 
presents a number of enticing optimization opportunities.  But getting code into SSA form
can also make certain optimizations easier to reason about and write.  To take maximum
advantage of available optimization opportunities, the optimization pipeliner supports
"pre-scheduled" optimizations and "post-scheduled" optimizations.

Scheduling
========

GraphIR is a Sea-of-Nodes format which means all primops and continuations are "floating"
in a module.  In order to prepare GraphIR for emission as LLVM IR, it is necessary to impose
an ordering on continuations.  We call this process "scheduling".

