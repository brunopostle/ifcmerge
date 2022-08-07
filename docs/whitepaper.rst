Native IFC
==========

*A whitepaper introducing a fully collaborative BIM using open standards and open protocols*

Abstract
--------

A simple to implement set of protocols for reading and writing BIM data, known as Native IFC, enables robust multi-user collaborative BIM workflows.
We show how full version tracking, rollback, attribution, staging, merging, multi-user editing, issue tracking, automated checking, and publishing can be achieved by hosting IFC data in established commercial and open source git-forge services.
We show that the git revision control system as a Common Data Environment (CDE) for BIM data is scalable, secure, future-proof and fully interoperable with existing systems. 
We show multiple software applications and libraries that already implement Native IFC, this is a real-world technology that can be adopted today.

Motivation
----------

why the existing technology is inadequate to address the problem

Old paradigm, IFC export and read-only, federation for viewing other trades as overlays

Comparison with Revit worksharing

for these reasons, IFC is often mistakenly presented as a BIM version of PDF. this is not justified by the ifc specification which is clearly designed as a live editable database.

Native IFC Vs openbim

federation disadvantates, spatial containers not working with non-architectural elements. inability to step outside professional boundaries

Previous diff and patch approaches keyed from element GUIDs. STEP IDs are more robust, but require Native IFC compliant tools.

Rationale
---------

New paradigm, native IFC creating and editing IFC data in place

Step ID change tracking

Git for collaborative BIM, branch, fork, pull-request and merge

Git works both offline and online, asynchronous, supported by three way merge technology 

Single models are superior to federation, spatial containers working properly with non-architectural elements

Filters allow large single models to be opened and edited, same features as federated workflow but allowing container relationships and cross-discipline contribution

Federated models are still possible if required, git supports third-party repositories included as submodules 

Git allows chains of responsibility, precise change tracking and blame

Native IFC is easy to compare for online model comparison, viewing changes between commits and versions

Generation of documentation, 2d drawings, schedules etc.. from single IFC model can be automated using continuous integration tools

Continuous integration allows problems and status changes to be tracked and reported automatically bimchecker

Git forges have advanced bug/issue tracking and repository management. Complete replacement for CDE (common data environment)

Multiple Native IFC tools can work in the same IFC files without conflict. 

Git repositories contain full history, allowing all stages to be reconstructed at any time, only changes are stored and the database is compressed. So cloning a git repository with hundreds of individual commits likely to be less data than transferring a single model

Signed releases give precise revision and drawing-issue tracking

Git is an open standard, repositories can be hosted anywhere and transferred without loss to other forges, or stored locally. The repository format is future proof, data will be retrievable for the conceivable future

Git scales, in 2018 Microsoft moved their entire Windows codebase to a single 300gb repository

Scalability, ifcmerge tool merges 5mb of entities into a 10mb file in 9 seconds

Specification
-------------

Three native IFC requirements

A *Native IFC* application behaves in the following ways when editing a pre-existing IFC (STEP/SPF) file:

1. IFC entities *must* be written in the same format as received, with the same numeric IDs as before.

2. Attribute changes to entities *must* be written in-place.

3. Numeric IDs of deleted entities *must not* be reused for new entities.

Dion's native IFC definition 

Data is not mangled during I/O: Uses IFC as the source of truth. No translation to internal data models. There might be a slight edge case for canonicalised units though.

Data is never lost outside the application scope: Touches only the IFC subgraphs that is relevant to its function. No "side effects" of data loss or "domino effects" of data loss by touching data in one spot. E.g. editing an object attribute should not affect related materials, assigned tasks, or cost items.

Data is added without affecting existing data: Whether this extends to STEP IDs is a different question. I personally treat STEP IDs as being pretty critical to uniquely identify any little bit of IFC data, and so I'd expect something similar to this, either IDs, or clear ways of navigating from rooted entities should exist ideally for other non-STEP repositories to be useful.

Data is modified in place where possible: things like attributes and properties can be modified in place. However, there are some things that are ambiguous, like brep/tessellation shape representation subgraphs, which I treat as "trash and recreate". Though parametric extrusions I do edit in place. I guess this is still an area of exploration.

Data is exposed through the UI starting at rooted entities: the concept is that unless the Native IFC tool is some developer poweruser thing, the user should always be presented clearly with rooted entities as a starting point, which then access the auxiliary data. This allows some level of sanity of exchanging data with the ability to think in terms of rooted entities. There are some unfortunate exceptions to this, like materials and profiles which are critical to many disciplines but not given first class status.

In general, this does lead to pretty good plaintext diffs (unless the serialisation changes the string formatting which sometimes happens).

Backwards compatibility
-----------------------

Although Native IFC expects applications to take the steps described above to ensure file continuity, the files themselves are entirely normal standards-compliant IFC STEP files, which can still be imported by legacy applications.

A file maintained under Native IFC protocols can even be used within a legacy federated BIM collaboration setup, either as a read-only overlay imported into legacy tools, or using files exported by legacy tools as federated overlays. Such arrangements may last for the duration of multi-year construction projects without incurring additional administration costs.

Native IFC files are fully interoperable in any such OpenBIM scenario.

Security implications
---------------------

It is important to consider how a malicious actor could exploit any data protocol, such an attack could come from outside or inside a project team.

Confidentiality and read-only access control,

Copyright, theft of intellectual property.

Signed commits and authenticated version tagging. Staged commits. Drawback is that blaming becomes inescapable due to a full audit trail existing for all edits.

Closed or open design processes, pros and cons.

Reference Implementations
-------------------------

Native IFC is not an onerous standard.
From a software developers viewpoint, Native IFC is a rational design choice.
So we have independently developed tools written in C++/Python, Javascript and Perl that implement the standard without requiring any further modification.

`BlenderBIM`_, Python. Partially complete GUI IFC editing tool

`IfcOpenShell`_, C++/Python. Mature library for manipulating IFC data.

`IFC.js`_, Javascript. Work in progress library and web GUI

`File::IFC`_, Perl. Legacy stable library for reading and writing.

`ifcmerge`_, Perl. Proof of concept three-way merge of Native IFC files.

xbim?

Rejected Ideas
--------------

serverside single database with synchronous access.

guid tracking

About
-----

Text Copyright 2022, Bruno Postle and Dion Moult. The latest version of this document can be found at https://github.com/brunopostle/ifcmerge/blob/docs/whitepaper.rst

.. _BlenderBIM: https://blenderbim.org

.. _IfcOpenShell: https://github.com/IfcOpenShell/IfcOpenShell

.. _IFC.js: https://github.com/IFCjs

.. _File::IFC: https://bitbucket.org/brunopostle/file-ifc

.. _ifcmerge: https://github.com/brunopostle/ifcmerge
