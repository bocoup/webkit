/*
 * Copyright (C) 2004, 2005 Nikolas Zimmermann <zimmermann@kde.org>
 * Copyright (C) 2004, 2005, 2006 Rob Buis <buis@kde.org>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#pragma once

#include "SVGAnimatedString.h"
#include "SVGElement.h"

namespace WebCore {

class SVGFEMergeNodeElement final : public SVGElement {
    WTF_MAKE_ISO_ALLOCATED(SVGFEMergeNodeElement);
public:
    static Ref<SVGFEMergeNodeElement> create(const QualifiedName&, Document&);

private:
    SVGFEMergeNodeElement(const QualifiedName&, Document&);

    void parseAttribute(const QualifiedName&, const AtomicString&) final;
    void svgAttributeChanged(const QualifiedName&) final;
    bool rendererIsNeeded(const RenderStyle&) final { return false; }

    BEGIN_DECLARE_ANIMATED_PROPERTIES(SVGFEMergeNodeElement)
        DECLARE_ANIMATED_STRING(In1, in1)
    END_DECLARE_ANIMATED_PROPERTIES
};

} // namespace WebCore
