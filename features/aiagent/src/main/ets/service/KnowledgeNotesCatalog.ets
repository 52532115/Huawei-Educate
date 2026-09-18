/*
 * Copyright (c) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 */

import { SeedLectureInput } from '../viewmodel/KnowledgeModels';
import { buildCalculusOneNotes } from './KnowledgeNotesCalculus';
import { buildAlgebraNotes } from './KnowledgeNotesAlgebra';
import { buildProbabilityNotes } from './KnowledgeNotesProbability';
import { buildPhysicsNotes } from './KnowledgeNotesPhysics';
import { buildProgrammingNotes } from './KnowledgeNotesProgramming';
import { buildDataStructureNotes } from './KnowledgeNotesDataStructure';
import { buildComputerOrganizationNotes } from './KnowledgeNotesArchitecture';
import { buildOperatingSystemNotes } from './KnowledgeNotesOperatingSystem';
import { buildComputerNetworkNotes } from './KnowledgeNotesNetwork';
import { buildDatabaseNotes } from './KnowledgeNotesDatabase';
import { buildCompilerNotes } from './KnowledgeNotesCompiler';
import { buildSoftwareEngineeringNotes } from './KnowledgeNotesSoftware';
import { buildGraphicsNotes } from './KnowledgeNotesGraphics';
import { buildSecurityNotes } from './KnowledgeNotesSecurity';
import { buildMachineLearningNotes } from './KnowledgeNotesMl';
import { buildWebLinuxNotes } from './KnowledgeNotesWeb';

/**
 * The shipped course notes, one entry per course in the catalogue.
 *
 * This is the aggregation seam: the prose lives in per-subject files so each
 * stays readable, and everything downstream — the corpus adapter, the chunker,
 * the index, the store — sees only a flat list of `SeedLectureInput`.
 *
 * A note's `courseId` must match a row in `KnowledgeCourseCatalog`, otherwise
 * the course name in the citation would not agree with the catalogue the rest
 * of the app shows. That invariant is asserted in the offline tests rather than
 * enforced at runtime: a mismatch is a build-time authoring mistake, and
 * silently dropping notes at runtime would hide it.
 */
export function buildLectureNotes(): SeedLectureInput[] {
  const notes: SeedLectureInput[] = [];
  appendAll(notes, buildCalculusOneNotes());
  appendAll(notes, buildAlgebraNotes());
  appendAll(notes, buildProbabilityNotes());
  appendAll(notes, buildPhysicsNotes());
  appendAll(notes, buildProgrammingNotes());
  appendAll(notes, buildDataStructureNotes());
  appendAll(notes, buildComputerOrganizationNotes());
  appendAll(notes, buildOperatingSystemNotes());
  appendAll(notes, buildComputerNetworkNotes());
  appendAll(notes, buildDatabaseNotes());
  appendAll(notes, buildCompilerNotes());
  appendAll(notes, buildSoftwareEngineeringNotes());
  appendAll(notes, buildGraphicsNotes());
  appendAll(notes, buildSecurityNotes());
  appendAll(notes, buildMachineLearningNotes());
  appendAll(notes, buildWebLinuxNotes());
  return notes;
}

function appendAll(target: SeedLectureInput[], rows: SeedLectureInput[]): void {
  for (let i = 0; i < rows.length; i++) {
    target.push(rows[i]);
  }
}
