Native IFC
==========

*A white-paper introducing a collaborative BIM using open standards and open protocols*

[Note: this document is a work-in-progress, comments and contributions welcome]

Abstract
--------

A simple to implement set of protocols for reading and writing BIM data, known as *Native IFC*, enables robust multi-user collaborative BIM workflows.
We show how full version tracking, rollback, attribution, staging, merging, multi-user editing, issue tracking, automated checking, and publishing can be achieved by hosting IFC data in established commercial and open source git-forge services.
We show that the git revision control system as a Common Data Environment (CDE) for BIM data is scalable, secure, future-proof and fully interoperable with existing systems. 
We show multiple software applications and libraries that already implement *Native IFC*, this is a real-world technology.

Motivation
----------

Building Information Modelling (BIM) is a process of modelling entire buildings as things, information, and the relationships between them.

BIM is generally done with large software applications that keep their data in proprietary format files.
These are shared in what is called a Common Data Environment (CDE), effectively a file server that can be accessed remotely.

This way of doing Collaborative BIM has disadvantages: one of them is that such a system can't be called interoperable without exporting data to open formats such as `Industry Foundation Classes (IFC)`_ and sharing these exported files; this in turn means that it isn't practical for multiple people to contribute to the same model without problematic workarounds.

A system where data is exported from one application and imported into another is a one-way street.
Round-tripping through import/export necessarily involves data loss, design teams therefore construct workflows so that round-tripping never happens.
Where multiple trades and consultants are involved in a project, typically each will be given strictly delimited parts of the project to work-on, making their parts available to the rest of the team as a read-only reference.
This division of labour is termed 'federation', where each trade owns a separate file, usually with the architectural part providing overall coordination
(A proprietary form of this, worksharing, allows this division of labour to occur within a single file, but it requires that all users are using the same proprietary application).

Federation, with projects split into separate files by trade, has a notable disadvantage:
A selling-point of BIM is that it is not just objects and information, but relationships between this data.
With a federated model it isn't possible to define a relationship between elements that exist in separate files.
For example, spatial containers such as rooms and storeys are typically defined in an architectural model, a federated building services model can't assign equipment to these spaces as a result.
This is basic information that would be expected by a Facilities Management team after building handover.

Separating trades into silos that can't modify each other's data has other disadvantages:
A Structural engineer can't provisionally move a door in the architect's model; they have to create a drawing showing how they think the door should move, send it in an email to the architect, hoping then that the architect might update their model at some point -- eventually this moved door will cascade into the federated model that everyone sees.
Buildings are never constructed exactly as drawn; a responsible contractor will update a BIM model 'as-built', but these updates can't be fed-back upstream so that everybody has the same model, this would require import, update, export, import and export steps -- overwriting the upstream models in the process.

In contrast, the way we write and maintain software is not at all like the way buildings are designed with BIM.
Many software projects have lots of contributors, often working on the same files at the same time, using systems that scale to thousands of developers.

Software development has settled on a few collaborative practices and tools: we store our files in distributed systems like the `git version control system`_, and we work by 'forking' a copy, making local changes, then requesting that others 'pull' our changes, merging them with their own.

This collaborative software development wouldn't be possible without a specific technology: the *three-way merge*.
A 'three-way merge' allows two people to make independent changes to the same file, then merge them together using the common 'ancestor' as a base reference.

We assert that what the AEC community needs is the equivalent of a 'three-way merge' for BIM data.
Consequently, this whitepaper introduces a working three-way merge tool for *Native IFC* data.
This *Native IFC* workflow enables genuine interoperable distributed BIM collaboration, reusing tools long available in the software world: `git-forge services`_ such as GitHub, trackers, discussion, tagging, releases and continuous integration.

Rationale
---------

We propose a new paradigm, creating and editing IFC data in-place without import/export translation to proprietary models, *Native IFC*.

We find that STEP/SPF ID change tracking allows robust three-way merging of IFC files.

The git revision control system is a good fit for collaborative BIM, enabling a modern branch, fork, pull-request and merge workflow.
Git is both an offline and online technology, permitting asynchronous working.
Git repositories contain full history, allowing all stages to be reconstructed at any time, only changes are stored and the database is compressed.
Cloning a git repository with hundreds of individual commits is likely to involve less data than transferring a single uncompressed model.
Git is an open standard, repositories can be hosted anywhere and transferred without loss to other forges, or stored locally.
Git scales, in 2017 the entire Microsoft `Windows code base moved to git`_ in a single 300 GiB repository.

We propose the use of single models in preference to existing federation practices.
Filters in BIM applications allow large single models to be opened and edited, this allows the same features as a federated workflow while allowing container and other relationships, plus enabling cross-discipline contribution.
Federated models are still possible if required, git supports third-party repositories included as 'submodules'.

Native IFC is easy to compare, viewing changes between arbitrary commits and versions is a basic requirement.

Git forges have advanced bug/issue tracking and repository management. These features provide a complete replacement CDE (common data environment)

Generation of documentation, 2D drawings, schedules etc.. from IFC models can be automated using continuous integration tools triggered by git 'commit hooks'.
Continuous integration allows problems and status changes to be tracked and reported automatically.
In the future, costings, carbon analysis, thermal, structural analysis, any number of other checks can all be performed for *every commit* - giving short feedback cycles needed when designing complex systems.

A basic feature of *Native IFC* is that as long as simple rules are followed, multiple tools from multiple vendors can work on the same IFC data without conflict.

Specification
-------------

Technical requirements
~~~~~~~~~~~~~~~~~~~~~~

A *Native IFC* application behaves in the following ways when editing a pre-existing IFC (STEP/SPF) file:

1. IFC entities *must* be written in the same format as received, with the same numeric IDs as before. Line ordering is *not* critical when serialising STEP files.

2. Attribute changes to entities *must* be written in-place, preserving the numeric ID of the entity.

3. Numeric IDs of deleted entities *must not* be reused for new entities.

General principles
~~~~~~~~~~~~~~~~~~

Data is not mangled during I/O, the IFC data is the source of truth.
This means that an application does not translate to internal data models and export back to IFC unless the user is modifying that bit of data.

Data is never lost outside the application scope: an application operation touches only the IFC subgraphs that is relevant to its function.
This means that there must be no 'side effects' or 'domino effects' of data loss by touching data in one spot.
E.g. editing an object attribute should not affect related materials, assigned tasks, or cost items.

Data is added without affecting existing data.
STEP/SPF IDs are critical to uniquely identify any little bit of IFC data.
So any non-STEP tool that used IFC GUIDs instead would need clear ways of navigating from rooted entities in order to map back and forth with ID preserving STEP repositories.

Data is modified in place where possible: things like attributes and properties can be modified in place.
However, there are some things that are ambiguous, like brep/tessellation shape representation subgraphs, which can be treated as 'trash and recreate' if they have been modified.
Though parametric extrusions and similar can be edited in-place, so they should.

Data is exposed through an application UI starting at rooted IFC entities.
The concept is that unless the Native IFC tool is some developer poweruser thing, the user should always be presented clearly with rooted entities as a starting point, which then access the auxiliary data.
This allows some level of sanity of exchanging data with the ability to think in terms of rooted entities.
There are some unfortunate exceptions to this, like materials and profiles which are critical to many disciplines but not given first class IFC status in the existing specification.

Backwards compatibility
-----------------------

Although Native IFC expects applications to take the steps described above to ensure file continuity, the files themselves are entirely normal standards-compliant IFC STEP files, which can still be imported by legacy applications.

A file maintained under Native IFC protocols can even be used within a legacy federated BIM collaboration setup, either as a read-only overlay imported into legacy tools, or using files exported by legacy tools as federated overlays. Such arrangements may last for the duration of multi-year construction projects without incurring additional administration costs.

Native IFC files are fully interoperable in any such `openBIM`_ scenario.

Security implications
---------------------

It is important to consider how a malicious actor could exploit any data protocol, such an attack could come from outside or inside a project team.

Confidentiality
~~~~~~~~~~~~~~~

There is a distinction between normal expectations of privacy of occupants and designers, and potential attacks on the building itself using privileged information (the subject of many movie plots from Star Wars on).
Most git-forge services allow fine-grained access control, including requiring multi-factor authentication for read-only access.

Intellectual property
~~~~~~~~~~~~~~~~~~~~~

As above, git-forge access control can offer read-only restrictions.
With git, since the authorship of every commit is recorded, it is possible to identify exactly the design ownership of models or part models.

A consideration is that there are advantages to allowing wider access to BIM models, some examples:
an active citizen may be entitled to examine publicly funded construction projects;
sharing best-practice can improve the general quality of construction;
a public URL that links directly to a view of a model using `BIM Collaboration Format (BCF)`_ would greatly aid communication between stakeholders;
and, as with open source software, there are often real benefits to liberal licenses that allow reuse of design work. 

Auditing
~~~~~~~~

With git as a version control system, all changes to a model can be traced precisely to author and date committed, either by trusting the git-forge authentication system or through pgp or s/mime signing of commits.

Reference Implementations
-------------------------

Native IFC is not an onerous standard.
From a software developers viewpoint, Native IFC is a rational design choice.
So we have identified independently developed tools written in languages as diverse as C++/Python, Javascript and Perl that implement the standard without requiring any further modification.

`BlenderBIM`_, Python. Partially complete GUI IFC editing and authoring tool.

`IfcOpenShell`_, C++/Python. Mature library for manipulating IFC data.

`IFC.js`_, Javascript. Work in progress library and web GUI.

`File::IFC`_, Perl. Legacy stable library for reading and writing.

`ifcmerge`_, Perl. Proof of concept three-way merge of Native IFC files.

xbim?

Rejected Ideas
--------------

Often offered as a solution is storing IFC data for a project in a single online relational or graph database.
This would allow synchronous access, preventing conflict through short-term and local-scope locking mechanisms.
We are not proposing this as a solution as it introduces a single point of failure.
A git based workflow is distributed and robust against network failure, gracefully falling-back to simple distribution methods such as email during network instability or server failure.

About
-----

Copyright 2022, Bruno Postle with additional text by Dion Moult. The latest version of this document can be found at https://github.com/brunopostle/ifcmerge/blob/main/docs/whitepaper.rst

.. _git version control system: https://git-scm.com/

.. _git-forge services: https://en.m.wikipedia.org/wiki/Forge_(software)

.. _Windows code base moved to git: https://devblogs.microsoft.com/bharry/the-largest-git-repo-on-the-planet/

.. _Industry Foundation Classes (IFC): https://technical.buildingsmart.org/standards/ifc

.. _BIM Collaboration Format (BCF): https://technical.buildingsmart.org/standards/bcf/

.. _openBIM: https://www.buildingsmart.org/about/openbim/

.. _BlenderBIM: https://blenderbim.org

.. _IfcOpenShell: https://github.com/IfcOpenShell/IfcOpenShell

.. _IFC.js: https://github.com/IFCjs

.. _File::IFC: https://bitbucket.org/brunopostle/file-ifc

.. _ifcmerge: https://github.com/brunopostle/ifcmerge
